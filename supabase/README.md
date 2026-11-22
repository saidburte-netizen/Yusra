# Supabase — Yusra Pharmacy

## Owner run order

### Existing live project (most likely)

The owner's project was created by running the original SQL steps by hand. If
`0001`–`0019` are already applied (including earlier proposals that may have
been run since), **do not re-run them**. Apply only the newer steps:

1. Open the Supabase SQL Editor.
2. If the project is still at `0018`, run `migrations/0019_hardening_fixes.sql`
   as one query (`0019_hardening_fixes.sql:17-557,781-831`).
3. Run, in filename order: `migrations/0020_fix_sale_return.sql`
   (final `process_sale_return`, `0020_fix_sale_return.sql:14-98`),
   `migrations/0021_grants.sql` (`0021_grants.sql:17-37`),
   `migrations/0022_opening_stock_reorder.sql`
   (`0022_opening_stock_reorder.sql:13-434`) and
   `migrations/0023_review_fixes.sql` (`0023_review_fixes.sql:10-563`).
4. Run `checks/schema_check.sql`; every row must be `PASS`, including the
   `0023` view/role guard rows (`checks/schema_check.sql:368-391`).
5. Re-run the optional `SMOKE_*` CI workflow against the live project.

`0019` is idempotent. It fixes invalid `PGRST116` error codes to `P0002`,
hardens every listed SECURITY DEFINER function, makes `handle_new_user`
default to `super_admin` with a safe invalid-role fallback, creates missing
profiles, adds `update_my_profile`, `customer_stats` and
`shift_expected_cash`, authorizes audit corrections and expense approvals,
blocks direct PO status/receipt writes, adds storage policies, and gives the
twelve report views stable `date` columns.

### Fresh or recovery project

Run `migrations/0001`–`0023` in filename order, **or** run the generated
`all_owner_sql.sql` once as a single query. The bundle carries `-- FILE:`
markers for every source file through `0023_review_fixes.sql`
(`all_owner_sql.sql:3671`), is safe to run twice, and is applied twice in
`db-test` CI (CI job `db-test`, `.github/workflows/ci.yml:32-627`).
`supabase/config.toml` pins PostgreSQL 16 and disables signup for local
development only (`supabase/config.toml`).

## Files

| File | Purpose |
| --- | --- |
| `migrations/0001`–`0011` | Original baseline schema, helpers, views, triggers and seed |
| `migrations/0012` | RLS policies, grants, private Storage buckets |
| `migrations/0013` | Void and return RPCs |
| `migrations/0014` | Twelve `v_report_*` views |
| `migrations/0015` | Team access RPCs |
| `migrations/0016` | `get_my_profile()` strict profile read |
| `migrations/0017` | Activity audit log and correction RPCs |
| `migrations/0018` | Default `super_admin` on first user, idempotent trigger |
| `migrations/0019` | Hardening and wire fixes described above (`0019_hardening_fixes.sql:17-557,781-831`) |
| `migrations/0020` | Final `process_sale_return`, fixing the `0013` text/enum bug (`0020_fix_sale_return.sql:14-98`) |
| `migrations/0021` | Consolidated grants (`0021_grants.sql:17-37`) |
| `migrations/0022` | Reorder columns, `v_reorder_suggestions`, opening-stock and draft-PO RPCs (`0022_opening_stock_reorder.sql:13-434`) |
| `migrations/0023` | **New:** role/branch guards and row-numbered validation for the `0022` RPCs and views (`0023_review_fixes.sql:10-563`) |
| `all_owner_sql.sql` | Full generated bundle for fresh/recovery projects, through `0023` (`all_owner_sql.sql:3671`) |
| `checks/schema_check.sql` | PASS/FAIL contract, now including the `0023` view/role guard checks (`checks/schema_check.sql:368-391`; its header still says "through 0022") |

## Verification

CI applies the bundle twice, then applies numbered migrations in order on a
clean PostgreSQL 16 service, runs `checks/schema_check.sql` (failing on any
FAIL row, including the `0023` view/role guard rows at
`checks/schema_check.sql:368-391`) and `tool/db_test.sql` (15 functional PASS
checks). This is the `db-test` job (`.github/workflows/ci.yml:32-627`). Locally,
with a PostgreSQL 16 database:

```bash
psql -v ON_ERROR_STOP=1 -f tool/supabase_stubs.sql
psql -v ON_ERROR_STOP=1 -f supabase/all_owner_sql.sql
psql -v ON_ERROR_STOP=1 -f supabase/all_owner_sql.sql
psql -v ON_ERROR_STOP=1 -f supabase/checks/schema_check.sql
psql -v ON_ERROR_STOP=1 -f tool/db_test.sql
```

## Owner manual actions

1. Apply `0019` if needed and then `0020`–`0023`, and confirm `schema_check.sql`
   is all PASS as described above (including the `0023` guard rows at
   `checks/schema_check.sql:368-391`).
2. In Supabase Auth, disable public Signup and configure redirect URLs for
   the deployed web origin; choose the email-confirmation policy.
3. Verify buckets `prescriptions`, `receipts`, `branding`, `avatars` and
   `medicine-images` and the `0019` policies. Receipts/Rx stay private;
   branding and medicine images are public.
4. Set Edge Function secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
   `SUPABASE_ANON_KEY` and `APP_ORIGIN`, then deploy `admin-create-user` and
   `admin-reset-password`.
5. Set the GitHub secrets documented in the root `README.md`.
6. Rotate any PAT that was previously pasted into chat.

## Database change protocol

Never change the live database from application code. Add the next numbered
migration (must be idempotent), regenerate `all_owner_sql.sql` from
`0001`–latest, extend `schema_check.sql`, and send the owner the exact SQL to
run. Only the owner runs it against the live project.

## CHANGELOG

| File | Status | Purpose |
| --- | --- | --- |
| 0001–0011 | Applied by owner / baseline | Original schema and seed |
| 0012–0018 | Applied on projects that ran earlier proposals | RLS, RPCs, reports, team access, profile RPC, audit, first-user default |
| 0019 | Applied or pending | Hardening, authorization and wire fixes (`0019_hardening_fixes.sql:17-557`) |
| 0020 | **New — owner must apply** | Final sale-return function (`0020_fix_sale_return.sql:14-98`) |
| 0021 | **New — owner must apply** | Consolidated grants (`0021_grants.sql:17-37`) |
| 0022 | **New — owner must apply** | Reorder view/columns and opening-stock / draft-PO RPCs (`0022_opening_stock_reorder.sql:13-434`) |
| 0023 | **New — owner must apply** | Role/branch guards and row-numbered validation (`0023_review_fixes.sql:10-563`) |
