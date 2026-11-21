# Supabase — Yusra Pharmacy

## Owner run order

### Existing live project (most likely)

The owner's project was created by running the original SQL steps by hand. If
`0001`–`0018` are already applied (including earlier proposals that may have
been run since), **do not re-run them**. Apply only the new remediation:

1. Open the Supabase SQL Editor.
2. Run `migrations/0019_hardening_fixes.sql` as one query.
3. Run `checks/schema_check.sql`; every row must be `PASS`.
4. Re-run the optional `SMOKE_*` CI workflow against the live project.

`0019` is idempotent. It fixes invalid `PGRST116` error codes to `P0002`,
hardens every listed SECURITY DEFINER function, makes `handle_new_user`
default to `super_admin` with a safe invalid-role fallback, creates missing
profiles, adds `update_my_profile`, `customer_stats` and
`shift_expected_cash`, authorizes audit corrections and expense approvals,
blocks direct PO status/receipt writes, adds storage policies, and gives the
twelve report views stable `date` columns.

### Fresh or recovery project

Run `migrations/0001`–`0019` in filename order, **or** run the generated
`all_owner_sql.sql` once as a single query. The bundle carries `-- FILE:`
markers for every source file, is safe to run twice, and is applied twice in
`db-test` CI. `supabase/config.toml` pins PostgreSQL 16 and disables signup
for local development only.

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
| `migrations/0019` | **New:** hardening and wire fixes described above |
| `all_owner_sql.sql` | Full generated bundle for fresh/recovery projects |
| `checks/schema_check.sql` | PASS/FAIL contract through `0019` |

## Verification

CI applies the bundle twice, then applies numbered migrations in order on a
clean PostgreSQL 16 service, runs `checks/schema_check.sql` (failing on any
FAIL row) and `tool/db_test.sql` (15 functional PASS checks). Locally, with a
PostgreSQL 16 database:

```bash
psql -v ON_ERROR_STOP=1 -f tool/supabase_stubs.sql
psql -v ON_ERROR_STOP=1 -f supabase/all_owner_sql.sql
psql -v ON_ERROR_STOP=1 -f supabase/all_owner_sql.sql
psql -v ON_ERROR_STOP=1 -f supabase/checks/schema_check.sql
psql -v ON_ERROR_STOP=1 -f tool/db_test.sql
```

## Owner manual actions

1. Apply `0019` and confirm `schema_check.sql` is all PASS as described above.
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
| **0019** | **New — owner must apply** | Hardening, authorization and wire fixes |
