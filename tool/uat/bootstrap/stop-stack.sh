#!/usr/bin/env bash
# Tear down the local UAT stack. Safe to run after a failed bootstrap.
set -euo pipefail

if [[ -f /tmp/uat-functions.pid ]]; then
  pid="$(cat /tmp/uat-functions.pid)"
  kill "$pid" 2>/dev/null || true
  rm -f /tmp/uat-functions.pid
fi
rm -f "${RUNNER_TEMP:-/tmp}/uat-functions.env"

supabase stop > /tmp/uat-supabase-stop.log 2>&1 || {
  tail -40 /tmp/uat-supabase-stop.log >&2 || true
}

echo "UAT stack stopped."
