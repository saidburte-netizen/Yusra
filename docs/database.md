# Database reference — Yusra Pharmacy

The SQL steps in `supabase/migrations/` are the source of truth for columns. This is a map for developers.

## Owner run order

- **Existing project with `0001`–`0019` applied:** run `0020_fix_sale_return.sql`
  (final `process_sale_return`), `0021_grants.sql`, `0022_opening_stock_reorder.sql`
  then `0023_review_fixes.sql`, then `checks/schema_check.sql`; expect all PASS
  (`supabase/migrations/0020_fix_sale_return.sql:14-98`,
  `0021_grants.sql:17-37`, `0022_opening_stock_reorder.sql:13-434`,
  `0023_review_fixes.sql:10-563`, `supabase/checks/schema_check.sql:232-391`).
- **Existing project with only `0001`–`0018` applied:** run `0019_hardening_fixes.sql`
  first, then the `0020`–`0023` sequence above.
- **Fresh/recovery project:** run `0001`–`0023` in filename order or the
  generated `all_owner_sql.sql` once, which bundles through
  `0023_review_fixes.sql` (`supabase/all_owner_sql.sql:3671`).
- Never re-run older migrations on the live project. See `supabase/README.md`
  for the exact owner action list.

## Roles

`app_role`: `super_admin`, `admin`, `pharmacist`, `cashier`, `store_keeper`, `accountant`.
`super_admin` sees every branch; every other role is scoped to `profiles.branch_id`. Helpers in `0002`:

- `my_role()` — caller's active role
- `my_branch()` — caller's branch
- `has_role(variadic app_role[])` — role test
- `can_access_branch(uuid)` — super admin or own branch

`has_role` and `can_access_branch` are also enforced inside the newer
`SECURITY DEFINER` RPCs (`0023_review_fixes.sql:385-390,536-541`) and inside
views built over `branches` (`0023_review_fixes.sql:10-135`,
`supabase/checks/schema_check.sql:368-391`).

## Tables

| Group | Tables |
| --- | --- |
| Identity | `branches`, `profiles`, `app_settings`, `doc_counters`, `audit_logs` |
| Catalogue | `categories`, `medicines` (SKU, barcode, prices, VAT flag, Rx flag, controlled flag, `reorder_point` / `reorder_qty` at `0022_opening_stock_reorder.sql:13-24`), `suppliers` |
| Purchasing | `purchase_orders` (status `draft`/`ordered`/`partially_received`/`received`/`cancelled`), `purchase_order_items` (generated `line_total`) |
| Stock | `stock_batches` (batch no, expiry, qty, cost, supplier, PO), `stock_movements` (`opening`, `purchase`, `sale`, `sale_return`, `void_restore`, `adjustment`, `expired_writeoff`, `damage`) |
| Sales | `customers`, `prescriptions` (`pending`/`dispensed`/`cancelled`), `shifts` (`open`/`closed`, one open shift per user), `sales` (`completed`/`voided`/`partially_returned`/`returned`), `sale_items`, `sale_payments` (`cash`/`mobile_money`/`card`/`bank_transfer`), `sale_returns`, `sale_return_items` |
| Finance | `expenses` |

All money columns are `numeric(14,2)`. Prices exclude VAT; ETB, whole units only.

## Views (read only, `security_invoker`)

- `v_stock_summary` — available quantity per branch and medicine
- `v_low_stock` — at/below reorder level
- `v_expiring_batches` — batches near expiry
- `v_reorder_suggestions` — medicines at/below `reorder_point` with suggested
  `reorder_qty` (`0022_opening_stock_reorder.sql:31-136`); final definition
  filters with `can_access_branch()` (`0023_review_fixes.sql:47-63,82-135`)
- `v_daily_sales` — per-day totals in `Africa/Addis_Ababa`
- Twelve `v_report_*` views — created in `0014`, corrected in `0019` with stable `date` columns: sales by day/cashier/payment method/medicine, profit, stock valuation, expiry losses, purchases by supplier, expenses, net profit, shift variance and the controlled-drug register. All twelve expose `branch_id` so a super admin can filter a report by branch; everyone else is scoped by RLS. They are the only source of report aggregates; the app never recomputes financial figures in Dart.

## RPCs — the only writers for stock and money

| RPC | Purpose |
| --- | --- |
| `add_stock_batch(branch, medicine, batch_no, expiry, qty, cost, supplier)` | New batch; rejects non-future expiry and empty batch no; the 7-argument overload treats `NULL` cost as zero (`0023_review_fixes.sql:348-362`) |
| `adjust_stock(batch, change, type, reason)` | Adjustment / write-off / damage; rejects negative resulting stock |
| `receive_purchase_order(po, items)` | `{po_item_id, quantity, batch_no, expiry_date}`; creates batches and `purchase` movements |
| `open_shift(branch, opening_cash)` | Opens a shift; enforces one open shift per user |
| `close_shift(shift, closing_cash, note)` | Returns `{expected_cash, closing_cash, difference}` |
| `create_sale(branch, shift, customer, prescription, items, payments, discount, note)` | FEFO allocation, expired batch exclusion, Rx check, discount limit, payments, document numbers |
| `void_sale(sale, reason)` | Voids a completed sale and restores stock (0013, hardened in 0019) |
| `process_sale_return(sale, items, reason, refund_method)` | Returns and optionally restocks (0013, hardened in 0019); **final definition is `0020_fix_sale_return.sql:14-98`**, which fixes the earlier text/enum bug |
| `set_user_access(user, role, branch, active)` | Changes one teammate's role/branch/status and JWT metadata; super admin only for super-admin roles (0015, hardened in 0019) |
| `share_admin_access(targets uuid[])` | Copies the caller's role and branch to selected teammates (0015, hardened in 0019) |
| `publish_app_settings()` | Publishes global settings to the team and writes an audit entry (0015, hardened in 0019) |
| `update_my_profile(name, phone, avatar_url)` | Safe self-service profile fields only; role/branch/active are rejected (0019) |
| `set_purchase_order_status`, `approve_purchase_order`, `cancel_purchase_order` | RPC-only PO status transitions; direct writes are blocked by trigger (0019) |
| `set_expense_status`, `approve_expense`, `reject_expense` | Accountant/admin approval workflow (0019) |
| `request_activity_correction`, `approve_activity_correction` | Permission-checked audit corrections (0017, authorized in 0019) |
| `get_my_profile`, `customer_stats`, `shift_expected_cash` | Strict profile read and financial/stats helpers (0016/0019) |
| `add_opening_stock(branch, rows jsonb)` | Opening-stock rows validated with row numbers, then batches + `opening` movements (`0022_opening_stock_reorder.sql:143-256`; final role/branch guard and validation at `0023_review_fixes.sql:367-514`) |
| `create_draft_purchase_orders(branch, lines jsonb)` | Reorder lines → draft POs (`0022_opening_stock_reorder.sql:323-434`; final role/branch guard and validation at `0023_review_fixes.sql:519-563`) |

`next_doc_no(prefix, branch)` generates `INV`, `PO`, `RX` and `RET` numbers; it is revoked from `anon` and `authenticated` and is called only by triggers and RPCs. Every SECURITY DEFINER function sets `search_path`, revokes from `public, anon` and grants execute to `authenticated` (`0019_hardening_fixes.sql:781-795`). Stock/money RPCs use the `app.via_rpc` guard so triggers can distinguish RPC writes from direct table writes (`0007_functions.sql:86`, `0009_triggers.sql:54-77`, `0022_opening_stock_reorder.sql:383-416`); every view built over `branches` filters with `can_access_branch()` (`0023_review_fixes.sql:10-195`, `supabase/checks/schema_check.sql:368-391`). Invalid `PGRST116` lookups now raise `P0002` (0019).

## Triggers

- `trg_<table>_updated` — `set_updated_at()` on 12 tables
- `trg_po_numbering`, `trg_rx_numbering` — document numbers
- `trg_po_total_calc`, `trg_poi_recalc` — purchase order totals
- `trg_po_guard` — only admin approves/cancels; receiving only through RPC
- `trg_profiles_protect` — role/branch/active protection; admins cannot touch super admins
- `trg_<table>_audit` — `audit_row()` on 12 tables

## Permission matrix

`E` edit, `V` view, `own` own records only, `–` none. S=super_admin, A=admin, P=pharmacist, C=cashier, K=store_keeper, F=accountant.

| Module | S | A | P | C | K | F |
| --- | - | - | - | - | - | - |
| dashboard | V | V | V | V | V | V |
| users and roles | E | E | – | – | – | – |
| team access (extension) | E | V | – | – | – | – |
| branches | E | V | – | – | – | – |
| settings | E | E | – | – | – | – |
| audit log | V | V | – | – | – | – |
| medicines, categories | E | E | E | V | E | V |
| stock batches, adjust | E | E | E | V | E | V |
| suppliers | E | E | V | – | E | V |
| purchase orders | E | E | V | – | E | V |
| POS | E | E | E | E | – | – |
| sales history | V | V | V | own | – | V |
| void, returns | E | E | E | – | – | – |
| shifts | V | V | V | own | – | V |
| customers | E | E | E | E | – | V |
| prescriptions | E | E | E | V | – | – |
| expenses | E | E | – | – | – | E |
| reports | V | V | – | – | – | V |

Cost prices are hidden from cashiers in the UI. Enforced by RLS in
`supabase/migrations/0012_rls_hardening.sql:18-221`; direct writes to stock and
money tables are blocked by trigger (`0012_rls_hardening.sql:169-172`).
