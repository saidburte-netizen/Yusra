# Connectivity — end-to-end business flow wiring

This document traces every business flow from the screen the user touches to the
database object that stores it, the policy that authorises it, the trigger that
records it, the report that aggregates it and the dashboard tile that surfaces
it. Every hop cites a real `file:line` in this repository. It complements
`docs/SCREEN_MATRIX.md` (screen states), `docs/database.md` (schema/permission
reference) and `docs/AUDIT.md` (wire-check), and is the map to use when changing
one layer so the other layers are not broken.

## How to read the traces

Each flow is written as a fixed nine-hop chain:

1. **Screen** — route and widget that starts the flow (route file `path:` line,
   or `lib/core/router.dart` for the central routes).
2. **Provider** — Riverpod provider that supplies the screen's data or holds the
   repository/client reference.
3. **Repository** — Dart method that performs the read or write. "Screen
   client" means the screen calls `SupabaseService.client` directly; this is a
   known structural gap, not a separate class.
4. **RPC / table** — the PostgREST call and the SQL definition of the target
   function/table (`supabase/migrations/...:line`). Stock and money writes are
   RPCs only; master data is written through RLS-protected tables.
5. **RLS** — the policy that scopes the read/write (`supabase/migrations/0012_rls_hardening.sql`
   is the branch/role policy layer; `0017`, `0019`, `0022` add more).
6. **Triggers** — numbering, recalculation, guard and `activity_log` triggers.
7. **Audit log** — the append-only trail: `audit_logs` (row-level `audit_row()`)
   and `activity_log` (actor/role-aware `write_activity_log()`).
8. **Report view** — the `v_report_*` view (all `security_invoker`, all defined
   in `0014_report_views.sql` and corrected in `0019_hardening_fixes.sql`) that
   aggregates the flow, plus its Dart definition where one exists.
9. **Dashboard tile** — the card on `/dashboard` and the `DashboardRepository`
   method that loads it. "No dedicated tile" is called out explicitly.

Shared foundations: one Supabase client (`lib/core/supabase_client.dart:20-44`),
branch scoping from the auth profile (`lib/features/inventory/data/inventory_providers.dart:17-22`),
and the RPC-only-writer rule (`docs/database.md:46-67`) apply to every flow.

---

## 1. Procurement (purchase orders)

1. **Screen** — `/purchasing/orders` `PurchaseOrdersScreen`, `/purchasing/orders/new`
   and `/purchasing/orders/:id` `PurchaseOrderScreen` (`lib/features/purchasing/purchasing_routes.dart:9,13,17`).
2. **Provider** — `purchaseOrdersProvider`, `purchaseOrderProvider`,
   `purchaseItemsProvider` (`lib/features/purchasing/data/purchasing.dart:253,260,273`).
3. **Repository** — `PurchaseRepository.orders/order/items` (`:113,125,131`),
   `createDraft` (`:146`), `saveLines` (`:191`), `setStatus` (`:211`),
   `receive` (`:240`).
4. **RPC / table** — `purchase_orders`, `purchase_order_items` writes; draft
   header/line inserts at `purchasing.dart:154-173` and `:191-203`; status only
   through `set_purchase_order_status` / `approve_purchase_order` /
   `cancel_purchase_order` (`supabase/migrations/0019_hardening_fixes.sql:312,357,363`)
   with the legacy-name fallback loop at `purchasing.dart:211-238`; receiving
   through `receive_purchase_order` (`0007_functions.sql:65`, replaced at
   `0019_hardening_fixes.sql:373`).
5. **RLS** — branch/role read `rls_po_read` / `rls_poi_read`
   (`0012_rls_hardening.sql:71,75`); write `rls_po_write` / `rls_poi_write`
   (`:150,154`) restricted to `super_admin,admin,pharmacist,store_keeper`;
   status/receipt guards `trg_po_guard` (`0019:290`) and
   `trg_poi_receipt_guard` (`0019:309`).
6. **Triggers** — `trg_po_numbering` (`0009_triggers.sql:18`),
   `trg_po_total_calc` (`:38`), `trg_poi_recalc` (`:51`); updated-at on all
   tables (`0009:6`).
7. **Audit log** — `activity_po` (`0017_activity_audit.sql:72-74`) writes the
   actor/role row into `activity_log`; `audit_row()` on the 12 tracked tables
   (`0009_triggers.sql:116,127`) writes `audit_logs`.
8. **Report view** — `v_report_purchases_supplier` (`0014_report_views.sql:120`,
   Dart key `purchasesSupplier` at `lib/features/reports/data/reports.dart:36`);
   received batches also feed `v_report_stock_valuation` (`0014:95`).
9. **Dashboard tile** — "Purchase orders to receive" (`lib/features/dashboard/dashboard_screen.dart:804-805`)
   from `DashboardRepository.ordersToReceive` (`lib/features/dashboard/dashboard_metrics.dart:126-133`).

## 2. Opening stock

1. **Screen** — `/inventory/opening-stock` `OpeningStockScreen`
   (`lib/features/inventory/inventory_routes.dart:40`); bulk CSV preview in
   `lib/features/inventory/logic/opening_stock_csv.dart`.
2. **Provider** — uses `inventoryRepositoryProvider`
   (`lib/features/inventory/data/inventory_providers.dart:12-13`); there is no
   opening-stock-specific provider — the screen calls the repository directly.
3. **Repository** — `InventoryRepository.addOpeningStock`
   (`lib/features/inventory/data/inventory_repository.dart:217-228`), one
   all-or-nothing RPC call.
4. **RPC / table** — `add_opening_stock` (`supabase/migrations/0022_opening_stock_reorder.sql:143`)
   validates every row before writing and inserts `stock_batches` plus
   `stock_movements` with `movement_type = 'opening'` (`0022:248-250`); the
   single-batch path is `add_stock_batch` (`0022:31,123`, originally
   `0007_functions.sql:1`).
5. **RLS** — read `rls_batches_read` / `rls_movements_read`
   (`0012_rls_hardening.sql:79,83`); there is deliberately **no** direct write
   policy on stock tables — see "RPCs — the only writers" in
   `docs/database.md:46` and the grants in `0021_grants.sql`.
6. **Triggers** — `activity_stock` (`0017:69-71`), `trg_<table>_updated`
   (`0009:6`), audit row trigger (`0009:116,127`).
7. **Audit log** — `activity_log` via `activity_stock`; `audit_logs` via
   `audit_row()` (`0009:116`).
8. **Report view** — `v_report_stock_valuation` (`0014:95`) and
   `v_reorder_suggestions` (`0022:263`) read the resulting `stock_batches`.
9. **Dashboard tile** — Low stock / Expiring soon / Expired cards
   (`lib/features/dashboard/dashboard_screen.dart:700-722`) from `v_low_stock`
   and `v_expiring_batches` via `DashboardRepository.lowStock/expiringBatches`
   (`lib/features/dashboard/dashboard_metrics.dart:101-111`).

## 3. Stock in (add batch, receive, adjust, stocktake)

1. **Screen** — `/inventory/batches` `BatchesScreen`, `/inventory/adjustments`
   `AdjustmentsScreen`, `/inventory/stocktake` `StocktakeScreen`, and
   `/inventory/medicines/:id` (`lib/features/inventory/inventory_routes.dart:36,48,60,26`).
2. **Provider** — `batchesProvider`, `movementsProvider`, `stockSummaryProvider`
   (`lib/features/inventory/data/inventory_providers.dart:60,69,39`).
3. **Repository** — `InventoryRepository.addStock`
   (`inventory_repository.dart:187-214`, RPC at `:197`), `adjustStock`
   (`:253-264`, RPC at `:259`), `batches` (`:140`), `movements` (`:160`);
   GRN path `PurchaseRepository.receive` (`purchasing.dart:240-244`).
4. **RPC / table** — `add_stock_batch` (`0007_functions.sql:1-34`; hardened
   `0022:31-122`), `adjust_stock` (`0007:36-63`),
   `receive_purchase_order` (`0019:373-447`); target tables `stock_batches`,
   `stock_movements` (movement types `opening`, `purchase`, `adjustment`,
   `expired_writeoff`, `damage` — `docs/database.md:32`).
5. **RLS** — `rls_batches_read`, `rls_movements_read`
   (`0012:79,83`, `can_access_branch`); writer role checks are inside the
   SECURITY DEFINER functions (`0007:14,46-57`, `0022:56`).
6. **Triggers** — `activity_stock` (`0017:69-71`), `trg_<table>_updated`
   (`0009:6`), `audit_row()` (`0009:116,127`).
7. **Audit log** — `activity_log` + `audit_logs`, as in flow 2.
8. **Report view** — `v_report_stock_valuation` (`0014:95`),
   `v_report_expiry_losses` (`0014:108`).
9. **Dashboard tile** — Low stock / Expiring soon / Expired
   (`dashboard_screen.dart:700-722`, `dashboard_metrics.dart:101-111`).

## 4. Reorder (needs ordering / alerts → draft PO)

1. **Screen** — `/inventory/needs-ordering` `NeedsOrderingScreen`, with
   `/inventory/alerts` `AlertsScreen` (`lib/features/inventory/inventory_routes.dart:44,56`).
2. **Provider** — `reorderSuggestionsProvider`
   (`lib/features/inventory/data/inventory_providers.dart:79-83`), auto-disposed
   and keyed by branch.
3. **Repository** — `InventoryRepository.reorderSuggestions`
   (`inventory_repository.dart:230-238`) and `createDraftPurchaseOrders`
   (`:241-251`).
4. **RPC / table** — `v_reorder_suggestions` (read; `0022_opening_stock_reorder.sql:263-313`),
   `create_draft_purchase_orders` (write; `0022:323`) inserts
   `purchase_orders` + `purchase_order_items` grouped per supplier.
5. **RLS** — `security_invoker = true` on the view (`0022:263`), revoked from
   `anon` and granted to `authenticated` (`0022:315-316`); PO writes still gated
   by `rls_po_write` (`0012:150`).
6. **Triggers** — `trg_po_numbering` (`0009:18`) and `activity_po`
   (`0017:72-74`) fire on the created drafts.
7. **Audit log** — `activity_log` via `activity_po`; `audit_logs` via
   `audit_row()` (`0009:116,127`).
8. **Report view** — `v_report_purchases_supplier` (`0014:120`) once the draft
   becomes `ordered`; `reports.dart:36` exposes it to the e2e suite.
9. **Dashboard tile** — "Purchase orders to receive"
   (`dashboard_screen.dart:804-805`, `dashboard_metrics.dart:126-133`).

## 5. Sale (POS)

1. **Screen** — `/pos` `PosScreen` (`lib/features/pos/pos_routes.dart:7`);
   history list `/sales` (`lib/features/sales/sales_routes.dart:9`).
2. **Provider** — `myOpenShiftProvider`, `salesProvider`,
   `receiptSettingsProvider` (`lib/features/sales/data/sales.dart:638,659,613`).
3. **Repository** — `SalesRepository.createSale`
   (`sales.dart:405-426`, RPC at `:415`), `sales` (`:449`), `saleItems`
   (`:499`), `salePayments` (`:510`); cart rules in
   `lib/features/sales/logic/cart.dart`, receipts in `lib/features/sales/logic/receipts.dart`.
4. **RPC / table** — `create_sale` (`supabase/migrations/0007_functions.sql:189-...`):
   requires an open own shift, FEFO allocation, Rx check, discount limit,
   `next_doc_no('INV', branch)`; writes `sales` (`0007:240`), checks Rx
   (`:250`), inserts `sale_items` (`:265`), decrements `stock_batches`
   (`:268`) and inserts `stock_movements` (`:270`), with the discount limit at
   `:285`.
5. **RLS** — `rls_sales_read`, `rls_sale_items_read`, `rls_sale_payments_read`
   (`0012:95,99,104`): branch-scoped and cashiers see only their own sales;
   every write is through the SECURITY DEFINER RPC.
6. **Triggers** — `activity_sales` (`0017:75-77`), `trg_<table>_updated`
   (`0009:6`), `audit_row()` (`0009:116,127`).
7. **Audit log** — `activity_log` row per sale insert/update; `audit_logs` row
   per tracked table write.
8. **Report view** — `v_report_sales_by_day` (`0014:15`),
   `v_report_sales_by_cashier` (`0014:28`), `v_report_sales_payment` (`0014:39`),
   `v_report_sales_by_medicine` (`0014:50`), `v_report_profit` (`0014:64`),
   `v_report_controlled_register` (`0014:178`); Dart keys at
   `lib/features/reports/data/reports.dart:26-43` and
   `lib/features/reports/reports_screen.dart:46-135`.
9. **Dashboard tile** — "Today's sales", "Monthly sales", "Gross profit today",
   top-medicines chart and sales chart
   (`lib/features/dashboard/dashboard_screen.dart:663-685,900-913`) from
   `DashboardRepository.salesBetween/saleItemsBetween`
   (`lib/features/dashboard/dashboard_metrics.dart:71-99`) and the Dart helpers
   `dashboardTopMedicines` / `dashboardGrossProfit`
   (`dashboard_metrics.dart:28,47`).

## 6. Return / void

1. **Screen** — `/sales/:id` `SaleDetailScreen` (partial return + void) and
   `/sales/returns` `ReturnsScreen` (`lib/features/sales/sales_routes.dart:19,15`).
2. **Provider** — `saleProvider`, `saleItemsProvider`, `salePaymentsProvider`,
   `saleReturnsProvider` (`lib/features/sales/data/sales.dart:667,672,678,684`).
3. **Repository** — `SalesRepository.voidSale` (`sales.dart:428-432`, RPC at
   `:429`) and `processReturn` (`:434-447`, RPC at `:440`), `saleReturns`
   (`:522-533`).
4. **RPC / table** — `void_sale` (`supabase/migrations/0013_rpc_gaps.sql:11-47`)
   writes `void_restore` stock movements (`:35-36`) and sets `sales.status =
   'voided'` (`:41-42`); `process_sale_return` (`0013:49-...`, replaced by
   `supabase/migrations/0020_fix_sale_return.sql:14-98`) inserts
   `sale_returns` (`0020:50`) + `sale_return_items` (`0020:79`), `sale_return`
   stock movements (`0020:71-72`) and sets `partially_returned`/`returned`
   (`0020:87`).
5. **RLS** — `rls_returns_read` / `rls_return_items_read`
   (`0012:109,113`) scope branch and `processed_by = auth.uid()` for cashiers;
   `rls_sales_read` (`0012:95`) covers the status update.
6. **Triggers** — `activity_returns` (`0017:78-80`) and `activity_sales`
   (`0017:75-77`) fire on the writes; `trg_<table>_updated` (`0009:6`).
7. **Audit log** — both `activity_log` and `audit_logs`; corrections to either
   go through `request_activity_correction` / `approve_activity_correction`
   (`0017:104,113`, re-authorised in `0019:158,191`).
8. **Report view** — voided sales are excluded from all `v_report_*` sales
   views (`0014:25,36,47,61,71,80`); `v_report_sales_by_medicine` subtracts
   `returned_qty` (`0014:53-57`).
9. **Dashboard tile** — sales totals read from `sales` via `salesBetween`
   (`lib/features/dashboard/dashboard_metrics.dart:71-82`); there is **no**
   dedicated return/void tile (gap).

## 7. Shift (open / close / Z report)

1. **Screen** — `/shifts` `ShiftsScreen` (`lib/features/shifts/shifts_routes.dart:7`);
   POS open/close banner in `lib/features/pos/screens/pos_screen.dart`.
2. **Provider** — `shiftsProvider` and `myOpenShiftProvider`
   (`lib/features/sales/data/sales.dart:651,638`).
3. **Repository** — `SalesRepository.openShift` (`sales.dart:334-342`, RPC at
   `:335`), `closeShift` (`:381-392`, RPC at `:386`), `shift` (`:344`),
   `myOpenShift` (`:353`), `shiftSaleCount` (`:395`).
4. **RPC / table** — `open_shift` (`0007_functions.sql:129-147`, one open shift
   per user) and `close_shift` (`0007:149-...`, returns
   `expected_cash/closing_cash/difference`), writing `shifts`; helper
   `shift_expected_cash` (`0019_hardening_fixes.sql:536`).
5. **RLS** — `rls_shifts_read` (`0012:91-92`): branch scoped, and cashiers see
   only rows where `cashier_id = auth.uid()`.
6. **Triggers** — `activity_shifts` (`0017:84-86`), `trg_<table>_updated`
   (`0009:6`), `audit_row()` (`0009:116,127`).
7. **Audit log** — `activity_log` (open/close) + `audit_logs`.
8. **Report view** — `v_report_shift_variance` (`0014:166-176`, corrected at
   `0019:668`), Dart key `shiftVariance` (`lib/features/reports/data/reports.dart:39`).
9. **Dashboard tile** — "Open shifts" (`lib/features/dashboard/dashboard_screen.dart:686-698`)
   from `DashboardRepository.openShifts` (`lib/features/dashboard/dashboard_metrics.dart:113-117`).

## 8. Expense

1. **Screen** — `/expenses` `ExpensesScreen` (`lib/core/router.dart:108`);
   receipt upload from `lib/features/expenses/expenses_screen.dart:264-269`.
2. **Provider** — none dedicated: the screen watches `authProvider` for role
   gating and reads/writes via the client directly
   (`lib/features/expenses/expenses_screen.dart:91-120,242-262`). **Gap:** a
   repository/provider pair like the other flows would make this testable
   through PostgREST in the same way.
3. **Repository** — "Screen client": reads at `expenses_screen.dart:108`,
   insert/update at `:185,193`, delete at `:231`, approval at `:251`.
4. **RPC / table** — `expenses` table; status changes only through
   `set_expense_status` (`0019_hardening_fixes.sql:467`), `approve_expense`
   (`:500`), `reject_expense` (`:506`); receipt files in storage bucket
   `receipts` (policies `0019:570,577`).
5. **RLS** — `rls_expenses_read` (`0012:119-120`), `rls_expenses_write`
   (`0012:164-166`, role-gated), guard `trg_expense_status_guard` (`0019:464`).
6. **Triggers** — `activity_expenses` (`0017:81-83`), `trg_expense_status_guard`
   (`0019:464`), `trg_<table>_updated` (`0009:6`).
7. **Audit log** — `activity_log` via `activity_expenses`; `audit_logs` via
   `audit_row()` (`0009:116,127`).
8. **Report view** — `v_report_expenses` (`0014:131-138`) and
   `v_report_net_profit` (`0014:140-164`); Dart keys at `reports.dart:37,38`.
9. **Dashboard tile** — **no dedicated expense tile**; expenses reach the
   dashboard only indirectly if the business computes net profit from the
   report (the dashboard cards at `dashboard_screen.dart:663-742` do not read
   `v_report_net_profit`). Gap.

## 9. Prescription

1. **Screen** — `/prescriptions` `PrescriptionsScreen`
   (`lib/features/prescriptions/prescriptions_routes.dart:7`), with the POS
   "new sale from Rx" link; image upload in `prescriptions_screen.dart`.
2. **Provider** — `prescriptionsProvider`
   (`lib/features/prescriptions/data/prescriptions.dart:127-137`), branch-scoped
   including the super-admin all-branch case.
3. **Repository** — `PrescriptionsRepository.list/create/cancel/markDispensed`
   (`prescriptions.dart:19,40,71,79`) and `uploadImageBytes/signedImageUrl`
   (`:95,120`).
4. **RPC / table** — `prescriptions` table insert at `prescriptions.dart:66-67`,
   status updates at `:71-92`, `sale_id` link from `create_sale`
   (`0007_functions.sql` Rx check), storage bucket constant at
   `prescriptions.dart:17`; Rx document numbers from `trg_rx_numbering`
   (`0009_triggers.sql:29`).
5. **RLS** — `rls_rx_read` (`0012:87-88`) and `rls_rx_write`
   (`0012:160-162`, `super_admin,admin,pharmacist`); image storage policies
   `rls_rx_storage_read/write/delete` (`0012:208,215,220`).
6. **Triggers** — `trg_rx_numbering` (`0009:29`), `activity_prescriptions`
   (`0017:90-92`), `trg_<table>_updated` (`0009:6`).
7. **Audit log** — `activity_log` via `activity_prescriptions`; `audit_logs`
   via `audit_row()` (`0009:116,127`).
8. **Report view** — `v_report_controlled_register` joins `prescriptions` for
   prescriber/patient (`0014:178-191`; grants re-issued at
   `0019_hardening_fixes.sql:757,771`); Dart key `controlledRegister`
   (`reports.dart:41-43`).
9. **Dashboard tile** — "Pending prescriptions"
   (`lib/features/dashboard/dashboard_screen.dart:724-741`) from
   `DashboardRepository.pendingPrescriptions`
   (`lib/features/dashboard/dashboard_metrics.dart:119-124`).

## 10. Reporting

1. **Screen** — `/reports` `ReportsScreen` (`lib/core/router.dart:112`); the
   twelve `ReportDef` entries are at `lib/features/reports/reports_screen.dart:46-135`.
2. **Provider** — `reportRowsProvider` (`reports_screen.dart:178-196`), which
   applies the same branch/date filters as the e2e-facing repository.
3. **Repository** — `ReportsRepository.rows/allForBranch` and the parallel
   `reportDefinitions` list (`lib/features/reports/data/reports.dart:25-86`).
4. **RPC / table** — the twelve `v_report_*` views defined in
   `supabase/migrations/0014_report_views.sql:15,28,39,50,64,95,108,120,131,140,166,178`
   and corrected in `0019_hardening_fixes.sql:630-721`. Read-only by design.
5. **RLS** — every view is `security_invoker = true` (`0014:15` etc., rationale
   at `0014:8-10`) and `anon` is revoked (`0014:194+`); branch scoping comes
   from the underlying table policies in flow 5-9.
6. **Triggers** — none on views. Reports consume the data written by the
   triggers in flows 1-9; this is intentional (aggregation lives in SQL).
7. **Audit log** — reports do **not** read the audit log; the audit trail is a
   separate screen (`/admin/audit`, `lib/core/router.dart:132`) fed by
   `activityProvider` (`lib/core/activity/activity.dart:56-87`).
8. **Report view** — the views themselves are the single source of truth; the
   app never recomputes financial figures in Dart (`docs/database.md:44`).
9. **Dashboard tile** — the dashboard uses its *own* reads
   (`DashboardRepository`, `lib/features/dashboard/dashboard_metrics.dart:64-154`)
   rather than the `v_report_*` views — it shares only `v_low_stock` and
   `v_expiring_batches`. Note this dual-path design when changing an aggregate.

## 11. User management (and audit corrections)

1. **Screen** — `/admin/users` `UsersScreen` (`lib/core/router.dart:116`),
   `/admin/team` `TeamAccessScreen` (`:120`), `/admin/audit` `AuditScreen`
   (`:132`), self-service `/profile` (`:104`); login/profile loading in
   `lib/core/auth/auth_controller.dart:159-191`.
2. **Provider** — `authProvider` (`auth_controller.dart`) and
   `activityProvider` (`lib/core/activity/activity.dart:56-87`, with Realtime
   refresh at `:73-84`).
3. **Repository** — no single repository; screens call RPCs directly:
   `set_user_access` (`lib/features/admin/users_screen.dart:259,288`),
   `share_admin_access` (`lib/features/admin/team_access_screen.dart:146-149`),
   `publish_app_settings` (`team_access_screen.dart:181`,
   `settings_screen.dart:226`), `update_my_profile`
   (`lib/features/auth/profile_screen.dart:89`), and correction RPCs
   (`lib/core/activity/activity.dart:101,108`). User create/reset-password go
   to the Edge Functions (`supabase/functions/admin-create-user/index.ts:43`,
   `supabase/functions/admin-reset-password/index.ts`); the profile read is
   `get_my_profile` (`auth_controller.dart:177`).
4. **RPC / table** — `get_my_profile` (`0016_profile_rpc.sql:9`),
   `set_user_access` (`0015_team_management.sql:15`, hardened `0019:17`),
   `share_admin_access` (`0015:98`), `publish_app_settings` (`0015:140`),
   `update_my_profile` (`0019:213`), `handle_new_user`
   (`0002:50`, replaced `0018:4` and `0019:99`); tables `profiles`, `branches`,
   `app_settings`, `audit_logs`.
5. **RLS** — `rls_profiles_read`, `rls_branches_read`, `rls_settings_read`
   (`0012:47,44,51`), `rls_audit_read` (`0012:54`),
   `rls_activity_read` (`0017:96-98`); storage policies for avatars/branding
   (`0019:583-609`); `trg_profiles_protect` blocks privilege escalation
   (`0009:98`).
6. **Triggers** — `on_auth_user_created` (`0002:64`, recreated `0019:140`),
   `trg_profiles_protect` (`0009:98`), `activity_profiles`
   (`0017:66-68`).
7. **Audit log** — `set_user_access` and `publish_app_settings` insert into
   `audit_logs` (`0015:83,160`); every profile/settings write also produces an
   `activity_log` row (`0017:66-68`); corrections are gated by
   `request_activity_correction` / `approve_activity_correction`
   (`0019:158,191`).
8. **Report view** — team identity joins the sales/shift reports:
   `v_report_sales_by_cashier` (`0014:28-37`) and `v_report_shift_variance`
   (`0014:166-176`).
9. **Dashboard tile** — "Team members" card
   (`lib/features/dashboard/dashboard_screen.dart:913-932`) from
   `DashboardRepository.teamMembers` (`lib/features/dashboard/dashboard_metrics.dart:146-153`),
   and the activity feed (`dashboard_screen.dart:840-884`) from
   `activityProvider` / `DashboardRepository.activityLog`
   (`dashboard_metrics.dart:135-144`).

---

## 12. Live drug status + dismissible low-stock alerts

1. **Screen** — `/inventory/drug-status` `DrugStatusScreen`
   (`lib/features/inventory/inventory_routes.dart`); reached from the Inventory
   chips, drawer, dashboard card and bell/dashboard alert banner.
2. **Provider** — `drugStatusProvider`, `lowStockAlertThresholdProvider`,
   `lowStockAlertsProvider`, `lowStockAlertCountProvider`,
   `stockAlertRealtimeProvider`
   (`lib/features/inventory/data/drug_status_providers.dart`). It joins
   `stockSummaryProvider` + `medicinesProvider` + `reorderSuggestionsProvider`,
   sorts lowest first and subscribes to `stock_batches` and `sales` via
   Supabase realtime; the shell watches the subscription once.
3. **Repository** — `InventoryRepository.createDraftPurchaseOrders` and the new
   `dismissLowStockAlert` / `dismissAllLowStockAlerts`
   (`lib/features/inventory/data/inventory_repository.dart`); every mutation is
   routed through `lib/core/state/invalidation.dart`.
4. **RPC / table** — `dismiss_low_stock_alert(p_medicine, p_branch)` and
   `dismiss_all_low_stock_alerts(p_branch)` are admin/security-definer RPCs;
   `stock_alert_dismissals` stores `medicine_id`, `branch_id`, `dismissed_by`,
   `dismissed_at`, `qty_at_dismiss` with branch-scoped admin RLS
   (`supabase/migrations/0028_low_stock_alerts.sql`).
5. **View / trigger** — `v_low_stock_alerts` reopens an alert when quantity
   drops below `qty_at_dismiss`; `trg_stock_batches_clear_low_stock_alert`
   deletes the dismissal once available stock reaches the global threshold.
6. **Settings** — `app_settings.low_stock_alert_threshold` defaults to 5 and is
   super-admin editable in `lib/features/admin/settings_screen.dart`.
7. **Activity** — both RPCs insert actor/role/summary rows into `activity_log`,
   which feeds `activityProvider` and the dashboard activity panel.
8. **Dashboard tile** — role-gated `Drug status` card and admin-only banner in
   `lib/features/dashboard/dashboard_screen.dart`; the bell uses the same
   `lowStockAlertCountProvider` for super admin/admin.
9. **Order path** — each Low/Out card calls the existing 0022 draft-PO RPC with
   one line (`supplier_id`, `medicine_id`, `quantity`, `unit_cost`) and opens
   `/purchasing/orders/:id`.

---

## Cross-cutting observations

- **Write authority is centralised in SQL, not Dart.** Every stock/money
  mutation is a `SECURITY DEFINER` RPC with an in-function role check
  (`docs/database.md:46-67`, e.g. `0007:14-20`, `0019:312-365`). The client's
  branch scope (`inventory_providers.dart:17-22`) is a usability filter; RLS is
  the actual security boundary (`0012:69-120`).
- **Two append-only logs exist and are not redundant.** `audit_logs`
  (`0002:101`, `audit_row()` at `0009:116`) is row-level old/new data;
  `activity_log` (`0017:6-22`, `write_activity_log()` at `0017:28-61`) is the
  actor/role/summary feed shown in the UI and on the dashboard, with a
  super-admin-only correction workflow (`0017:104-121`).
- **Master data is deactivated, never deleted**; immutable history tables
  (stock movements, sales, returns) are voided/reversed instead — see the
  "Notes" in `docs/SCREEN_MATRIX.md:53-71`.
- **Known wiring gaps to close in code (not docs):** (a) expenses has no
  repository/provider layer (flow 8); (b) reports have two parallel
  definitions (`reports_screen.dart:46` and `reports.dart:25`) that must be kept
  in sync; (c) the dashboard does not read the `v_report_*` views (flow 10);
  (d) there is no return/void or expense dashboard tile (flows 6 and 8).
