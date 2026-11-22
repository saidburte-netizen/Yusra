#!/usr/bin/env bash
# Runs Playwright against the already-bootstrapped local stack.
#
# Runtime credentials are read from `supabase status` into this shell only;
# they are never written to GITHUB_ENV, a file or the job log.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

eval "$(bash bootstrap/env.sh)"

exec npx playwright test "$@"
