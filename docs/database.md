# Database reference — Yusra Pharmacy

The SQL steps in `supabase/migrations/` are the source of truth for columns. This is a map for developers.

## Owner run order

- **Existing project with `0001`–`0018` applied:** run only
  `0019_hardening_fixes.sql`, then `checks/schema_check.sql`; expect all PASS.
- **Fresh/recovery project:** run `0001`–`0019` in filename order or the
  generated `all_owner_sql.sql` once; it is idempotent and was verified twice
  on PostgreSQL 16 in CI.
- Never re-run older migrations on the live project. See `supabase/README.md`
  for the exact owner action list.

## Roles

`app_role`: `super_admin`, `admin`, `pharmacist`, `cashier`, `store_keeper`, `accountant`.
`super_admin` sees every branch; every other role is scoped to `profiles.branch_id`. Helpers in `0002`:

- `my_role()` — caller's active role
- `my_branch()` — caller's branch
- `has_role(variadic app_role[])` — role test
- `can_access_branch(uuid)` — super admin or own branch

## Tables

| Group | Tables |
| --- | --- |
| Identity | `branches`, `profiles`, `app_settings`, `doc_counters`, `audit_logs` |
| Catalogue | `categories`, `medicines` (SKU, barcode, prices, VAT flag, Rx flag, controlled flag, reorder level), `suppliers` |
| Purchasing | `purchase_orders` (status `draft`/`ordered`/`partially_received`/`received`/`cancelled`), `purchase_order_items` (generated `line_total`) |
| Stock | `stock_batches` (batch no, expiry, qty, cost, supplier, PO), `stock_movements` (`opening`, `purchase`, `sale`, `sale_return`, `void_restore`, `adjustment`, `expired_writeoff`, `damage`) |
| Sales | `customers`, `prescriptions` (`pending`/`dispensed`/`cancelled`), `shifts` (`open`/`closed`, one open shift per user), `sales` (`completed`/`voided`/`partially_returned`/`returned`), `sale_items`, `sale_payments` (`cash`/`mobile_money`/`card`/`bank_transfer`), `sale_returns`, `sale_return_items` |
| Finance | `expenses` |

All money columns are `numeric(14,2)`. Prices exclude VAT; ETB, whole units only.

## Views (read only, `security_invoker`)

- `v_stock_summary` — available quantity per branch and medicine
- `v_low_stock` — at/below reorder level
- `v_expiring_batches` — batches near expiry
- `v_daily_sales` — per-day totals in `Africa/Addis_Ababa`
- Twelve `v_report_*` views — created in `0014`, corrected in `0019` with stable `date` columns: sales by day/cashier/payment method/medicine, profit, stock valuation, expiry losses, purchases by supplier, expenses, net profit, shift variance and the controlled-drug register. All twelve expose `branch_id` so a super admin can filter a report by branch; everyone else is scoped by RLS. They are the only source of report aggregates; the app never recomputes financial figures in Dart.

## RPCs — the only writers for stock and money

| RPC | Purpose |
| --- | --- |
| `add_stock_batch(branch, medicine, batch_no, expiry, qty, cost, supplier)` | New batch; rejects non-future expiry and empty batch no |
| `adjust_stock(batch, change, type, reason)` | Adjustment / write-off / damage; rejects negative resulting stock |
| `receive_purchase_order(po, items)` | `{po_item_id, quantity, batch_no, expiry_date}`; creates batches and `purchase` movements |
| `open_shift(branch, opening_cash)` | Opens a shift; enforces one open shift per user |
| `close_shift(shift, closing_cash, note)` | Returns `{expected_cash, closing_cash, difference}` |
| `create_sale(branch, shift, customer, prescription, items, payments, discount, note)` | FEFO allocation, expired batch exclusion, Rx check, discount limit, payments, document numbers |
| `void_sale(sale, reason)` | Voids a completed sale and restores stock (0013, hardened in 0019) |
| `process_sale_return(sale, items, reason, refund_method)` | Returns and optionally restocks (0013, hardened in 0019) |
| `set_user_access(user, role, branch, active)` | Changes one teammate's role/branch/status and JWT metadata; super admin only for super-admin roles (0015, hardened in 0019) |
| `share_admin_access(targets uuid[])` | Copies the caller's role and branch to selected teammates (0015, hardened in 0019) |
| `publish_app_settings()` | Publishes global settings to the team and writes an audit entry (0015, hardened in 0019) |
| `update_my_profile(name, phone, avatar_url)` | Safe self-service profile fields only; role/branch/active are rejected (0019) |
| `set_purchase_order_status`, `approve_purchase_order`, `cancel_purchase_order` | RPC-only PO status transitions; direct writes are blocked by trigger (0019) |
| `set_expense_status`, `approve_expense`, `reject_expense` | Accountant/admin approval workflow (0019) |
| `request_activity_correction`, `approve_activity_correction` | Permission-checked audit corrections (0017, authorized in 0019) |
| `get_my_profile`, `customer_stats`, `shift_expected_cash` | Strict profile read and financial/stats helpers (0016/0019) |

`next_doc_no(prefix, branch)` generates `INV`, `PO`, `RX` and `RET` numbers; it is revoked from `anon` and `authenticated` and is called only by triggers and RPCs. Every SECURITY DEFINER function sets `search_path`, revokes from `public, anon` and grants execute to `authenticated`. Invalid `PGRST116` lookups now raise `P0002` (0019).

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

Cost prices are hidden from cashiers in the UI. Enforced by RLS in `0012_rls_hardening.sql` (proposed).
