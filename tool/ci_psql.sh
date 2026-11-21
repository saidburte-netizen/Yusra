#!/usr/bin/env bash
# Run psql inside the postgres:16 service container.
# The GitHub runner's preinstalled psql may be an older major version, and
# apt does not always have postgresql-client-16 available. The service image
# always contains the matching client, so use that instead.
set -euo pipefail

cid="$(docker ps -q --filter ancestor=postgres:16 | head -n 1)"
if [[ -z "$cid" ]]; then
  echo "postgres:16 service container not found" >&2
  exit 1
fi

exec docker exec -i -e PGPASSWORD=postgres "$cid" psql -U postgres "$@"
