# Documentation index — Yusra Pharmacy

> This is the entry point for system documentation. Every description below
> points at the document that owns the detail; where a document is still being
> produced by another workstream it is marked **pending** rather than guessed
> at. Source-of-truth pointers: Flutter client `lib/main.dart:1-85`, SQL
> `supabase/migrations/0001_*.sql` … `0023_review_fixes.sql`
> (`supabase/all_owner_sql.sql:3671`), verification contract
> `supabase/checks/schema_check.sql:232-391`, CI entry point
> `.github/workflows/ci.yml:3-10`.

## Core architecture and maps

| Document | What it covers | Evidence anchor | Status |
| --- | --- | --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System context, layered folder map, DB ERD (tables/FKs/enums/RLS/RPCs/`SECURITY DEFINER`/`app.via_rpc`), auth + first-user `super_admin`, five business lifecycles, deployment topology, decision records, known limitations. Eight Mermaid diagrams with `file:line` citations. | `lib/main.dart:11-37`, `0001_extensions_enums.sql:4-10`, `0012_rls_hardening.sql:18-221`, `.github/workflows/ci.yml:32-627` | Available |
| [SCREEN_MATRIX.md](SCREEN_MATRIX.md) | Screen-by-screen route/state matrix, including `/inventory/opening-stock`, `/inventory/needs-ordering` and their RPCs/views. | `lib/core/router.dart:76-132`, `0022_opening_stock_reorder.sql:31-136,143-256` | Available |
| [ROLE_MATRIX.md](ROLE_MATRIX.md) | Generated roles, permissions and route/menu gating matrix. | `docs/ROLE_MATRIX.md:1-7`, `0001_extensions_enums.sql:4-10`, `lib/core/permissions.dart:77-249` | Available (generated; do not edit by hand) |
| [CONNECTIVITY.md](CONNECTIVITY.md) | Nine-hop traces from screen → provider → repository → RPC/table → RLS → trigger → audit → report → dashboard. | `docs/CONNECTIVITY.md:3-38` | Available |
| [WIRING_MATRIX.md](WIRING_MATRIX.md) | Cross-layer wiring checklist/results. | `tool/wiring_audit.dart`, `docs/CONNECTIVITY.md:3-9` | **Pending** — owned by another workstream |
| [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) | Riverpod providers, scoped cache and identity-change invalidation. | `lib/core/state/app_cache.dart:31-118`, `lib/features/inventory/data/inventory_providers.dart:12-88` | **Pending** — owned by another workstream |

## Data, testing and release

| Document | What it covers | Evidence anchor | Status |
| --- | --- | --- | --- |
| [database.md](database.md) | Schema/permission reference: tables, enums, RLS, RPC-only rule and migration guidance. *(Requested name `DATABASE.md`; tracked file is lowercase — see gap note.)* | `docs/database.md:46-67`, `supabase/migrations/0012_rls_hardening.sql:18-221` | Available (lowercase filename) |
| [test-plan.md](test-plan.md) | Test strategy and DB checks. *(Requested name `TEST_PLAN.md`; tracked file is lowercase — see gap note.)* | `docs/test-plan.md`, `supabase/checks/schema_check.sql:232-391`, CI job `db-test` | Available (lowercase filename) |
| [CICD.md](CICD.md) | GitHub Actions operating manual: PR gate jobs, artifacts, release, web deploy, Dependabot. | `docs/CICD.md:3-18`, CI jobs `toolchain`, `build`, `db-test`, `smoke-test`, `e2e-api`, `deploy-edge-functions` | Available |
| [SECURITY.md](SECURITY.md) | Threat model, secrets handling, service-role boundary, hardening guarantees. | `lib/core/env.dart:1-12`, `supabase/functions/admin-create-user/index.ts:1-2,43-68`, `0019_hardening_fixes.sql:781-795` | **Pending** — owned by another workstream |
| [PENTEST_REPORT.md](PENTEST_REPORT.md) | Penetration-test findings and remediation status. | `docs/SECURITY.md` (pending), `0019_hardening_fixes.sql:293-310,781-795` | **Pending** — owned by another workstream |
| [UAT_PLAN.md](UAT_PLAN.md) and other `docs/UAT_*.md` | User-acceptance-test scenarios and sign-off records. | `tool/uat/` | **Pending** — owned by another workstream |
| [AUDIT.md](AUDIT.md) | Historical screen/wire audit table; still describes the `0019` baseline and is **not** updated by this workstream. | `docs/AUDIT.md:11-46`, `README.md:37-39` | Available but stale |

Owned runbook outside `docs/`: [supabase/README.md](../supabase/README.md) —
migration/application order for Supabase project owners
(`supabase/README.md`, `supabase/config.toml`).

## Filename and drift notes

- The brief asks for `docs/DATABASE.md` and `docs/TEST_PLAN.md`; the repository
  tracks `docs/database.md` and `docs/test-plan.md` (no uppercase variants
  exist). Links above use the real tracked paths; the naming discrepancy is
  left for the docs owner to resolve (`docs/` directory listing;
  `docs/database.md`, `docs/test-plan.md`).
- Migration documentation drift: `README.md:37-39,67-81` and
  `docs/AUDIT.md:11-46` still reference `0019`, while the generated bundle
  reaches `0023_review_fixes.sql` (`supabase/all_owner_sql.sql:3671`).
- `supabase/checks/schema_check.sql` carries a "through 0022" header but now
  checks `0023` view/role guards (`supabase/checks/schema_check.sql:368-391`).
- Documents marked **pending** are owned by other workstreams; this index does
  not create or edit them.
