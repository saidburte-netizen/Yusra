# Supabase — Yusra Pharmacy

## Status of the live database

The owner created the live Supabase project by running the SQL steps **by hand in the Supabase SQL Editor**, in the order below. The files in `migrations/` are the repository record of exactly those steps. They are **already applied** — do not re-run them against the live project.

| File | Contents |
| --- | --- |
| `0001_extensions_enums.sql` | Extensions, enum types, `set_updated_at()` |
| `0002_core_tables_helpers.sql` | Branches, profiles, role/branch helpers, settings, document counters, audit log |
| `0003_catalog.sql` | SKU sequence, categories, medicines, suppliers |
| `0004_purchasing.sql` | Purchase orders and items |
| `0005_stock.sql` | Stock batches and movement ledger |
| `0006_sales_finance.sql` | Customers, prescriptions, shifts, sales, sale items/payments/returns, expenses |
| `0007_functions.sql` | Stock, purchasing, shift and sale RPCs |
| `0008_views.sql` | Stock, low-stock, expiry and daily-sales views |
| `0009_triggers.sql` | Updated-at, numbering, totals, guards and audit triggers |
| `0010_rls_storage.sql` | **Placeholder — see the important note below** |
| `0011_seed.sql` | Main branch, app settings, categories, super-admin placeholder, verification query |

`0012_rls_hardening.sql`, `0013_rpc_gaps.sql`, `0014_report_views.sql` and `0015_team_management.sql` are **proposed, not applied**. They follow the change protocol below and must be reviewed and run by the owner.

## Important — gaps in the supplied steps

The eleven steps supplied by the owner did **not** contain any `create policy`, `alter table ... enable row level security`, or `storage.buckets` statements; did not contain the `void_sale` or `process_sale_return` RPCs that the app calls; did not contain the twelve reporting views used by the Reports screen; and did not contain the team access RPCs. Consequently:

- `0010_rls_storage.sql` is intentionally empty of executable SQL so the repository stays honest about what was applied.
- `0012_rls_hardening.sql` proposes idempotent RLS policies, RPC grants and the five Storage buckets (`prescriptions`, `receipts`, `branding`, `avatars`, `medicine-images`).
- `0013_rpc_gaps.sql` proposes the void/return RPCs.
- `0014_report_views.sql` proposes the twelve `v_report_*` views with the exact columns the app queries.
- `0015_team_management.sql` proposes `set_user_access`, `share_admin_access` and `publish_app_settings` for super-admin team sharing.

**The owner must review and run 0012, 0013, 0014 and 0015 in the SQL Editor before the smoke test can pass and before Reports / Team access work against the live database.** Until then, direct table reads with the anon key are unrestricted by RLS and the role rules are only enforced in the client.

## Applying to a fresh project

1. Create a new Supabase project. The `extensions` schema must exist (it does by default).
2. Open the SQL Editor. Run each file one at a time, in filename order, as a single query. Stop if any file errors.
3. After `0011_seed.sql`, replace `PUT-THE-EMAIL-HERE` in the `update profiles` statement with the first admin's sign-up email (or run that `UPDATE` manually after the user signs up).
4. Review and run `0012_rls_hardening.sql`, `0013_rpc_gaps.sql`, `0014_report_views.sql` and `0015_team_management.sql`, in that order.
5. Run `checks/schema_check.sql` and confirm there are no `MISSING` rows.
6. Deploy the Edge Functions and set the GitHub secrets described in the root `README.md`.

Alternatively, install the Supabase CLI and run `supabase db push` — the files are plain, ordered SQL. The owner's live project was created manually, so the CLI is not required.

## Database change protocol

Never change the live database from application code. When any agent needs a change:

1. Add the next numbered file (`0016_name.sql`, and so on). It must be idempotent: `create or replace`, `create ... if not exists`, `drop policy if exists` before `create policy`, `add column if not exists`.
2. Add one line to the CHANGELOG below.
3. Send the owner a message headed **RUN IN SUPABASE SQL EDITOR** with the exact SQL and one line explaining what it does.
4. Only the owner runs it.

## CHANGELOG

| File | Status | Purpose |
| --- | --- | --- |
| 0001–0009, 0011 | Applied by owner | Original 11 SQL steps, copied verbatim |
| 0010 | Applied by owner | Placeholder — no RLS/Storage SQL was supplied |
| 0012 | **Proposed — not applied** | RLS policies, RPC grants, private prescriptions bucket |
| 0013 | **Proposed — not applied** | `void_sale` and `process_sale_return` RPCs |
| 0014 | **Proposed — not applied** | Twelve `v_report_*` reporting views |
| 0015 | **Proposed — not applied** | Team access RPCs: set role/branch, share access, publish settings |
