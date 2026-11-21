#!/usr/bin/env bash
# Helpers for the e2e-api CI job.
#
#   wait                         Wait until PostgREST answers GET /root.
#   create-user <id> <email> <role> <branch|""> <full-name>
#                                Create an auth.users row. The database's
#                                `on_auth_user_created` trigger creates the
#                                matching profile from raw_app_meta_data, which
#                                is exactly what the admin-create-user Edge
#                                Function does in production. This is the only
#                                hand-written SQL in the suite: auth.users is
#                                not exposed through the public PostgREST API.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${E2E_POSTGREST_URL:-http://127.0.0.1:3000}"

usage() {
  cat >&2 <<EOF
usage:
  $0 wait
  $0 create-user <uuid> <email> <app_role> <branch_uuid-or-empty> <full_name>
EOF
  exit 2
}

wait_for_postgrest() {
  echo "Waiting for PostgREST at $URL/ ..." >&2
  local deadline=$(( $(date +%s) + 90 ))
  until curl -fsS "$URL/" > /tmp/e2e-postgrest-root.json 2>/dev/null; do
    if (( $(date +%s) >= deadline )); then
      echo "PostgREST never became ready at $URL/" >&2
      curl -sS -i "$URL/" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "PostgREST ready:" >&2
  cat /tmp/e2e-postgrest-root.json >&2
  echo >&2
}

create_user() {
  if [[ $# -ne 5 ]]; then
    usage
  fi
  local id="$1" email="$2" role="$3" branch="$4" name="$5"
  local sql
  sql="insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values ('$id'::uuid, '$email', jsonb_build_object('role', '$role', 'branch_id', '$branch'), jsonb_build_object('full_name', '$name'));"
  bash "$ROOT/tool/ci_psql.sh" -d postgres -v ON_ERROR_STOP=1 -Atc "$sql"
}

case "${1:-wait}" in
  wait) wait_for_postgrest ;;
  create-user) shift; create_user "$@" ;;
  *) usage ;;
esac
