#!/usr/bin/env bash
# Seeds only the reference data a daily-work journey needs: two branches, six
# role users plus two cross-branch users, a supplier, a category and two
# medicines (one Rx-only, one normal). All writes go through GoTrue/PostgREST,
# never through hand-written SQL, so the UAT mirrors the production API path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
USERS_FILE="$ROOT/fixtures/users.json"

if [[ -z "${UAT_SUPABASE_URL:-}" ]]; then
  eval "$(bash "$ROOT/bootstrap/env.sh")"
fi

RUN="${UAT_RUN_ID:-uatlocal}"
URL="$UAT_SUPABASE_URL"

rest() {
  # rest <METHOD> <resource> <json-body>
  local method="$1" resource="$2" body="${3:-}"
  local out status payload
  out="$(curl -sS -X "$method" "$URL/rest/v1/$resource" \
    -H "apikey: $UAT_ANON_KEY" \
    -H "Authorization: Bearer $UAT_SERVICE_KEY" \
    -H 'Content-Type: application/json' \
    -H 'Prefer: return=representation' \
    --data "$body" -w '\n%{http_code}')"
  status="$(printf '%s\n' "$out" | tail -1)"
  payload="$(printf '%s\n' "$out" | sed '$d')"
  if [[ "$status" != 200 && "$status" != 201 && "$status" != 204 ]]; then
    echo "UAT seed: REST $method /$resource failed ($status): $payload" >&2
    return 1
  fi
  printf '%s' "$payload"
}

auth_admin() {
  # auth_admin <json-body> -> prints the created user JSON
  local body="$1" out status payload
  out="$(curl -sS -X POST "$URL/auth/v1/admin/users" \
    -H "apikey: $UAT_SERVICE_KEY" \
    -H "Authorization: Bearer $UAT_SERVICE_KEY" \
    -H 'Content-Type: application/json' \
    --data "$body" -w '\n%{http_code}')"
  status="$(printf '%s\n' "$out" | tail -1)"
  payload="$(printf '%s\n' "$out" | sed '$d')"
  if [[ "$status" != 200 && "$status" != 201 && "$status" != 409 ]]; then
    echo "UAT seed: GoTrue admin create user failed ($status): $payload" >&2
    return 1
  fi
  printf '%s' "$payload"
}

echo "== UAT seed: branches =="
BRANCH_A="$(rest POST branches "{\"name\":\"UAT Branch A $RUN\",\"code\":\"UATA${RUN: -10}\"}" | jq -r '.[0].id')"
BRANCH_B="$(rest POST branches "{\"name\":\"UAT Branch B $RUN\",\"code\":\"UATB${RUN: -10}\"}" | jq -r '.[0].id')"
[[ -n "$BRANCH_A" && "$BRANCH_A" != null && -n "$BRANCH_B" && "$BRANCH_B" != null ]] || {
  echo 'UAT seed: branch creation returned no ids' >&2
  exit 1
}
echo "   branch A=$BRANCH_A branch B=$BRANCH_B"

echo "== UAT seed: users (one per role + cross-branch admin/cashier) =="
SUPER_ID=''
while IFS= read -r entry; do
  key="$(printf '%s' "$entry" | jq -r '.key')"
  role="$(printf '%s' "$entry" | jq -r '.role')"
  branch_letter="$(printf '%s' "$entry" | jq -r '.branch')"
  password="$(printf '%s' "$entry" | jq -r '.password')"
  full_name="$(printf '%s' "$entry" | jq -r '.fullName')"
  if [[ "$branch_letter" == 'B' ]]; then branch="$BRANCH_B"; else branch="$BRANCH_A"; fi
  email="uat_${RUN}_$(printf '%s' "$entry" | jq -r '.local')@yusra.test"

  created="$(auth_admin "$(jq -nc \
    --arg email "$email" --arg password "$password" --arg role "$role" \
    --arg branch "$branch" --arg name "$full_name" \
    '{email:$email,password:$password,email_confirm:true,
      app_metadata:{role:$role,branch_id:$branch},
      user_metadata:{full_name:$name}}')")"
  user_id="$(printf '%s' "$created" | jq -r '.id // empty')"
  if [[ -z "$user_id" ]]; then
    echo "UAT seed: no id returned for $key ($email)" >&2
    exit 1
  fi
  # The profile is authoritative; make the fixture explicit even though the
  # handle_new_user trigger normally populates it from app_metadata.
  rest PATCH "profiles?id=eq.$user_id" "$(jq -nc \
    --arg role "$role" --arg branch "$branch" --arg name "$full_name" \
    '{role:$role,branch_id:$branch,full_name:$name,is_active:true}')" > /dev/null
  [[ "$key" == 'super_admin' ]] && SUPER_ID="$user_id"
  echo "   $key -> $email"
done < <(jq -c '.[]' "$USERS_FILE")

echo "== UAT seed: supplier, category and medicines =="
SUPPLIER_ID="$(rest POST suppliers "$(jq -nc --arg run "$RUN" \
  '{name:("UAT Supplier " + $run),contact_person:"UAT Contact",phone:"+251900000000",is_active:true}')" \
  | jq -r '.[0].id')"
CATEGORY_ID="$(rest POST categories "$(jq -nc --arg run "$RUN" \
  '{name:("UAT Category " + $run),is_active:true}')" | jq -r '.[0].id')"
NORMAL_ID="$(rest POST medicines "$(jq -nc --arg run "$RUN" --arg cat "$CATEGORY_ID" \
  '{name:("UAT Paracetamol 500mg " + $run),sku:("UATPAR" + ($run|.[-8:])),
    category_id:$cat,unit:"Pack",cost_price:2,selling_price:5,
    vat_applicable:true,requires_prescription:false,is_controlled:false,
    reorder_level:10,is_active:true}')" | jq -r '.[0].id')"
RX_ID="$(rest POST medicines "$(jq -nc --arg run "$RUN" --arg cat "$CATEGORY_ID" \
  '{name:("UAT Amoxicillin 500mg " + $run),sku:("UATAMX" + ($run|.[-8:])),
    category_id:$cat,unit:"Pack",cost_price:4,selling_price:9,
    vat_applicable:true,requires_prescription:true,is_controlled:false,
    reorder_level:10,is_active:true}')" | jq -r '.[0].id')"

echo "== UAT seed: one pending activity-log correction for super-admin approval =="
rest POST activity_log "$(jq -nc --arg id "$SUPER_ID" --arg branch "$BRANCH_A" --arg run "$RUN" \
  '{actor_id:$id,actor_email:"uat-cashier@yusra.test",actor_role:"cashier",
    action:"UPDATE",entity_type:"sales",entity_id:$run,branch_id:$branch,
    summary:("UAT seeded correction " + $run),
    correction_requested:true,correction_reason:"UAT seeded correction for approval"}')" > /dev/null

echo "   supplier=$SUPPLIER_ID category=$CATEGORY_ID normal=$NORMAL_ID rx=$RX_ID"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'UAT_BRANCH_A_ID=%s\n' "$BRANCH_A"
    printf 'UAT_BRANCH_B_ID=%s\n' "$BRANCH_B"
    printf 'UAT_SUPPLIER_ID=%s\n' "$SUPPLIER_ID"
    printf 'UAT_SUPPLIER_NAME=%s\n' "UAT Supplier $RUN"
    printf 'UAT_CATEGORY_ID=%s\n' "$CATEGORY_ID"
    printf 'UAT_NORMAL_MEDICINE_ID=%s\n' "$NORMAL_ID"
    printf 'UAT_RX_MEDICINE_ID=%s\n' "$RX_ID"
    printf 'UAT_NORMAL_MEDICINE_NAME=%s\n' "UAT Paracetamol 500mg $RUN"
    printf 'UAT_RX_MEDICINE_NAME=%s\n' "UAT Amoxicillin 500mg $RUN"
  } >> "$GITHUB_ENV"
fi
export UAT_BRANCH_A_ID="$BRANCH_A"
export UAT_BRANCH_B_ID="$BRANCH_B"
export UAT_SUPPLIER_ID="$SUPPLIER_ID"
export UAT_CATEGORY_ID="$CATEGORY_ID"
export UAT_NORMAL_MEDICINE_ID="$NORMAL_ID"
export UAT_RX_MEDICINE_ID="$RX_ID"

echo "== UAT seed: done =="
