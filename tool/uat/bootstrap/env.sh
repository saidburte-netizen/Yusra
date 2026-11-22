#!/usr/bin/env bash
# Emits `export ...` statements for the local Supabase stack. Intended to be
# evaluated: eval "$(bash tool/uat/bootstrap/env.sh)".
#
# Credentials are read from `supabase status` on every call and are NEVER
# written to disk or echoed by this script. Only the export lines for the
# consuming shell are printed.
set -euo pipefail

STATUS="$(supabase status -o json 2>/dev/null)"
read -r API ANON SERVICE DB <<< "$(
  printf '%s' "$STATUS" | jq -r '
    [ (.API_URL // .api_url // .api.url // ""),
      (.ANON_KEY // .anon_key // ""),
      (.SERVICE_ROLE_KEY // .service_role_key // ""),
      (.DB_URL // .db_url // "") ] | @tsv'
)"

if [[ -z "$API" || -z "$ANON" || -z "$SERVICE" ]]; then
  echo "UAT: could not read the local Supabase URL/keys from 'supabase status'." >&2
  echo "UAT: is the local stack running (bash tool/uat/bootstrap/start-stack.sh)?" >&2
  exit 1
fi

printf 'export UAT_SUPABASE_URL=%q\n' "$API"
printf 'export UAT_ANON_KEY=%q\n' "$ANON"
printf 'export UAT_SERVICE_KEY=%q\n' "$SERVICE"
[[ -n "$DB" ]] && printf 'export UAT_DB_URL=%q\n' "$DB"
printf 'export UAT_WEB_URL=%q\n' "${UAT_WEB_URL:-http://127.0.0.1:4173}"
