#!/usr/bin/env bash
# Run psql inside the postgres:16 service container.
# The GitHub runner's preinstalled psql may be an older major version, and
# apt does not always have postgresql-client-16 available. The service image
# always contains the matching client, so use that instead.
#
# The runner workspace is NOT mounted inside the service container, so a plain
# `psql -f path` would look for the SQL file inside the container and fail.
# Translate -f <host file> into -f - and stream the host file over stdin.
set -euo pipefail

cid="$(docker ps -q --filter ancestor=postgres:16 | head -n 1)"
if [[ -z "$cid" ]]; then
  echo "postgres:16 service container not found" >&2
  exit 1
fi

args=()
input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)
      if [[ $# -lt 2 ]]; then
        echo "ci_psql.sh: -f requires a host file path" >&2
        exit 2
      fi
      file="$2"
      if [[ ! -f "$file" ]]; then
        echo "ci_psql.sh: SQL file not found on runner: $file" >&2
        exit 2
      fi
      args+=(-f -)
      input="$file"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$input" ]]; then
  exec docker exec -i -e PGPASSWORD=postgres "$cid" psql -U postgres "${args[@]}" < "$input"
fi

exec docker exec -i -e PGPASSWORD=postgres "$cid" psql -U postgres "${args[@]}"
