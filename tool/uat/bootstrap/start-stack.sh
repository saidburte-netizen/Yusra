#!/usr/bin/env bash
# Stand up the complete local UAT stack:
#   1. Supabase CLI local stack (Postgres 16 + GoTrue + PostgREST + Storage)
#   2. Re-apply the consolidated owner bundle (all_owner_sql.sql is idempotent)
#   3. Serve the two admin Edge Functions locally
#   4. Seed branches, one user per role + cross-branch users, catalogue fixtures
#   5. Build the Flutter web app against the local anon key and serve it
#
# Run from anywhere. Credentials are read from `supabase status` at runtime and
# are never printed or committed. Non-secret run metadata (run id, branch ids)
# is exported to GITHUB_ENV when running in Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
cd "$REPO"

for tool in supabase docker flutter jq curl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "UAT: required tool '$tool' is not installed." >&2
    exit 1
  }
done

export UAT_RUN_ID="${UAT_RUN_ID:-$(printf 'uat%s' "$(date +%s)" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')}"
export UAT_RUN_ID="$(printf '%s' "$UAT_RUN_ID" | tr -cd '[:alnum:]_' | tr '[:upper:]' '[:lower:]')"
export UAT_WEB_URL="${UAT_WEB_URL:-http://127.0.0.1:4173}"

echo "== UAT $UAT_RUN_ID: starting Supabase local stack (output suppressed; no keys printed) =="
if ! supabase start > /tmp/uat-supabase-start.log 2>&1; then
  tail -100 /tmp/uat-supabase-start.log >&2
  exit 1
fi

eval "$(bash tool/uat/bootstrap/env.sh)"

echo "== UAT: applying supabase/all_owner_sql.sql (idempotent owner bundle) =="
DB_CONTAINER="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1 || true)"
if [[ -z "$DB_CONTAINER" ]]; then
  echo "UAT: no supabase_db_* container found." >&2
  exit 1
fi
docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
  < supabase/all_owner_sql.sql > /tmp/uat-owner-sql.log 2>&1 || {
  cat /tmp/uat-owner-sql.log >&2
  exit 1
}
echo "   all_owner_sql.sql: OK"

echo "== UAT: serving Edge Functions locally (admin-create-user, admin-reset-password) =="
FUNCTIONS_ENV="${RUNNER_TEMP:-/tmp}/uat-functions.env"
umask 077
{
  printf 'SUPABASE_URL=%s\n' "$UAT_SUPABASE_URL"
  printf 'SUPABASE_SERVICE_ROLE_KEY=%s\n' "$UAT_SERVICE_KEY"
  printf 'SUPABASE_ANON_KEY=%s\n' "$UAT_ANON_KEY"
} > "$FUNCTIONS_ENV"
nohup supabase functions serve --env-file "$FUNCTIONS_ENV" \
  > /tmp/uat-functions.log 2>&1 &
echo "$!" > /tmp/uat-functions.pid

echo "== UAT: seeding branches, users and catalogue fixtures =="
bash tool/uat/bootstrap/seed.sh
# seed.sh runs in a child shell; mirror the exact fixture names here so the
# parent (and therefore GITHUB_ENV below) can pass them to Playwright.
export UAT_SUPPLIER_NAME="UAT Supplier $UAT_RUN_ID"
export UAT_NORMAL_MEDICINE_NAME="UAT Paracetamol 500mg $UAT_RUN_ID"
export UAT_RX_MEDICINE_NAME="UAT Amoxicillin 500mg $UAT_RUN_ID"

echo "== UAT: building Flutter web (HTML renderer + local anon key) =="
flutter build web --release \
  --web-renderer html \
  --dart-define=SUPABASE_URL="$UAT_SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$UAT_ANON_KEY" \
  > /tmp/uat-flutter-build.log 2>&1 || {
  tail -100 /tmp/uat-flutter-build.log >&2
  exit 1
}
echo "   flutter build web: OK"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'UAT_RUN_ID=%s\n' "$UAT_RUN_ID"
    printf 'UAT_BRANCH_A_ID=%s\n' "${UAT_BRANCH_A_ID:-}"
    printf 'UAT_BRANCH_B_ID=%s\n' "${UAT_BRANCH_B_ID:-}"
    printf 'UAT_NORMAL_MEDICINE_ID=%s\n' "${UAT_NORMAL_MEDICINE_ID:-}"
    printf 'UAT_RX_MEDICINE_ID=%s\n' "${UAT_RX_MEDICINE_ID:-}"
    printf 'UAT_NORMAL_MEDICINE_NAME=%s\n' "${UAT_NORMAL_MEDICINE_NAME:-}"
    printf 'UAT_RX_MEDICINE_NAME=%s\n' "${UAT_RX_MEDICINE_NAME:-}"
    printf 'UAT_SUPPLIER_ID=%s\n' "${UAT_SUPPLIER_ID:-}"
    printf 'UAT_SUPPLIER_NAME=%s\n' "${UAT_SUPPLIER_NAME:-}"
    printf 'UAT_WEB_URL=%s\n' "$UAT_WEB_URL"
  } >> "$GITHUB_ENV"
fi

echo "== UAT stack ready =="
echo "   web:       $UAT_WEB_URL"
echo "   supabase:  $UAT_SUPABASE_URL"
echo "   run id:    $UAT_RUN_ID"
echo "   (keys are intentionally not printed)"
