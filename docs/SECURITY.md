# Security automation (Workstream 5)

This document explains how to run and interpret the repository-owned pentest
harness. Findings are in [PENTEST_REPORT.md](PENTEST_REPORT.md).

## Scope and ownership

This workstream changed only:

- `docs/SECURITY.md`, `docs/PENTEST_REPORT.md`
- `tool/pentest/**`
- `.github/workflows/security.yml`

No application code, SQL migration, e2e test, CI workflow (`ci.yml`), or other
workstream file was edited. The harness is **test infrastructure only**: it is
applied to a throwaway PostgreSQL 16 database, never to the Supabase project.

## CI job

- Workflow: `.github/workflows/security.yml:1`
- Job id **and** job name: `security` (`.github/workflows/security.yml:16-17`)
- Trigger: `pull_request` and `workflow_dispatch` (`.github/workflows/security.yml:8-10`)
- Postgres 16 service and apply step: `.github/workflows/security.yml:21-33`, `55-63`
- Orchestrator: `tool/pentest/run_all.sh:34-102`
- Artifacts: `security-reports` (`.github/workflows/security.yml:68-75`) and
  `security-screenshots` (`.github/workflows/security.yml:77-84`)

`run_all.sh` exits non-zero when any row has status `FAIL`
(`tool/pentest/run_all.sh:98-100`). `KNOWN-GAP` and `SKIP` rows do **not** fail
the job; they are recorded as documented owner actions or environment limits
(`tool/pentest/run_all.sh:102`).

### Making the check required

A workflow cannot set branch protection. A repository admin must add the status
check named exactly `security` to the protected branch's required checks, and
enable "Require branches to be up to date" if desired. Until that is done the
job runs and uploads artifacts but is advisory only.

## Local run

The SQL portion needs a plain PostgreSQL 16 server. With an empty database:

```bash
for f in tool/supabase_stubs.sql supabase/migrations/*.sql \
         tool/pentest/lib/pentest_helpers.sql tool/pentest/sql/fixtures.sql; do
  psql "$PENTEST_DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -f "$f"
done
PENTEST_DATABASE_URL="$PENTEST_DATABASE_URL" bash tool/pentest/run_all.sh
```

Without `PENTEST_DATABASE_URL` the shell checks still run and every SQL file is
recorded as `SKIP` (`tool/pentest/run_all.sh:54-57`). The local run on
2026-11-22 used a throwaway PostgreSQL 16 instance; CI uses the service in
`.github/workflows/security.yml:21-33`.

## Status vocabulary

| Status | Meaning | Source |
| --- | --- | --- |
| `PASS` | An existing protection behaved as asserted. | `tool/pentest/checks/common.sh:23` |
| `FAIL` | A protection regressed; the job fails. | `tool/pentest/checks/common.sh:24`, `tool/pentest/run_all.sh:98` |
| `KNOWN-GAP` | Real gap in an owner-owned file; documented, not a regression. | `tool/pentest/checks/common.sh:25`, `tool/pentest/lib/pentest_helpers.sql:67,227,276` |
| `SKIP` | Not runnable in this environment (live project, ZAP, parallel load, psql). | `tool/pentest/checks/common.sh:26` |
| `NOTE` | Scope or interpretation note. | `tool/pentest/checks/common.sh:27` |

Assertion helpers are in `tool/pentest/lib/pentest_helpers.sql:18-282`. They set
`request.jwt.claims.sub` and `SET LOCAL ROLE` to emulate anon/authenticated
callers. `pentest_expect_unchanged` (`:160`) is used where a trigger silently
restores a protected field instead of raising an error.

## File map

| Path | Purpose |
| --- | --- |
| `tool/pentest/lib/pentest_helpers.sql` | Result sink and role-switching assertions. |
| `tool/pentest/sql/fixtures.sql` | Two-branch deterministic users, stock, sales, storage objects. |
| `tool/pentest/sql/01_schema_hardening.sql` | RLS, grants, policies, SECURITY DEFINER, views, buckets. |
| `tool/pentest/sql/02_rls_matrix.sql` | Anon denial, cross-branch reads/writes, direct writes, escalation. |
| `tool/pentest/sql/03_rpc_abuse.sql` | RPC grants, cross-branch calls, input validation, SQLi, double actions. |
| `tool/pentest/sql/04_views_storage.sql` | Report-view isolation, storage path/bucket policies, unchecked RPCs. |
| `tool/pentest/checks/*.sh` | Secret, history, dependency, static, Android, web, Edge, live/ZAP checks. |
| `tool/pentest/run_all.sh` | Orchestrates checks, writes `artifacts/reports/**` and `artifacts/screenshots/**`. |

## Evidence and secret handling

- Reports contain statuses, test names, file:line references, and artifact
  paths only (`tool/pentest/checks/common.sh:16-20`).
- The secret scan reports `file:line` and never matched values
  (`tool/pentest/checks/secret_scan.sh:7-20`).
- No Supabase URL, service-role key, JWT, or other token is stored in this
  workstream's files. Live verification is explicitly skipped
  (`tool/pentest/checks/supabase_live.sh:5-6`).
- Screenshots are not generated locally because there is no deployed target;
  the artifact directory and its explanation are written by
  `tool/pentest/run_all.sh:12-18`.

## Known environment limits

- The live Supabase project cannot be verified locally: no URL or credentials
  are available to this harness (`tool/pentest/checks/supabase_live.sh:5`).
- OWASP ZAP baseline requires a deployed `PENTEST_TARGET_URL` and
  `zap-baseline.py` (`tool/pentest/checks/zap_baseline.sh:5-13`).
- True parallel-session concurrency testing is skipped; deterministic
  stock/double-action guards are covered in `tool/pentest/sql/03_rpc_abuse.sql`
  (`tool/pentest/checks/concurrency.sh:5-6`).
- No APK was built; Android findings are static manifest/Gradle checks
  (`tool/pentest/checks/android_checks.sh:10-44`).
