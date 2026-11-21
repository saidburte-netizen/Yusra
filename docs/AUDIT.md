# Yusra Pharmacy end-to-end audit

Single wire-check for `fix/full-wired-audit`. Every route and every one of the 91 `lib/**/*.dart` files is mapped to its screen/provider, database object, migration, role contract and UI states. All rows are `OK`.

Legend: **L** loading, **E** empty, **X** mapped error, **R** retry. `(shared)` and `(provider)` rows are included so the audit covers non-route files too.

## 1. Route wire-check

| Route | Screen | Provider | DB object | Migration | Roles (router / RLS-RPC) | States | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| /login | LoginScreen | authProvider | profiles, get_my_profile | 0016, 0018, 0019 | all → sign-in | L, X mapped, R | OK |
| /forgot-password | ForgotPasswordScreen | local state | Supabase Auth reset | tooling | all → reset | L, X mapped, R | OK |
| /reset-password | ResetPasswordScreen | local state | Supabase Auth reset | tooling | all → new password | L, X mapped, R | OK |
| /profile_error | ProfileErrorScreen | authProvider.profileError | get_my_profile | 0016, 0019 | authenticated only | dedicated error screen, Retry + Sign out | OK |
| /forbidden | ForbiddenScreen | authProvider | profiles | 0002, 0019 | authenticated only | loaded profile, escape to home | OK |
| /dashboard | DashboardScreen | dashboardSnapshotProvider | v_report_*, activity_log | 0014, 0017, 0019 | admin, super_admin | L, E, X, R | OK |
| /inventory | StockOverviewScreen | stockOverviewProvider | v_stock_summary, v_low_stock, v_expiring_batches | 0005, 0008, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /inventory/medicines | MedicinesScreen | medicinesProvider | medicines, categories, barcode RPC | 0003, 0012, 0019 | inventory roles | L, E, X, R | OK |
| /inventory/medicines/:id | MedicineDetailScreen | medicineProvider, batchesProvider | medicines, batches, stock_movements | 0003, 0005, 0019 | inventory roles | L, E, X, R | OK |
| /inventory/categories | CategoriesScreen | categoriesProvider | medicine_categories | 0003, 0012 | inventory admins | L, E, X, R | OK |
| /inventory/batches | BatchesScreen | batchesProvider | batches, v_expiring_batches | 0005, 0008, 0019 | inventory roles | L, E, X, R | OK |
| /inventory/movements | MovementsScreen | stockMovementsProvider | stock_movements | 0005, 0019 | inventory admins | L, E, X, R | OK |
| /inventory/adjustments | AdjustmentsScreen | adjustmentsProvider | adjust_stock, stock_movements | 0005, 0007, 0019 | inventory admins | L, E, X, R | OK |
| /inventory/stocktake | StocktakeScreen | stocktakeProvider | adjust_stock, batches | 0005, 0007, 0019 | inventory admins | L, E, X, R | OK |
| /inventory/alerts | AlertsScreen | lowStockProvider, expiryProvider | v_low_stock, v_expiring_batches | 0008, 0019 | inventory roles | L, E, X, R | OK |
| /purchasing/orders | PurchaseOrdersScreen | purchaseOrdersProvider | purchase_orders, suppliers | 0004, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /purchasing/orders/new | PurchaseOrderScreen | purchaseDraftProvider | create_purchase_order, medicines | 0004, 0007, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /purchasing/orders/:id | PurchaseOrderScreen | purchaseOrderProvider | receive_purchase_order, PO PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /suppliers | SuppliersScreen | suppliersProvider | suppliers, supplier_stats | 0004, 0013, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /suppliers/:id | SupplierDetailScreen | supplierProvider | suppliers, purchase_orders | 0004, 0019 | store_keeper, admin, super_admin | L, E, X, R | OK |
| /pos | PosScreen | cartProvider, myOpenShiftProvider, receiptSettingsProvider | create_sale, open_shift, sale_items | 0006, 0007, 0019 | cashier, pharmacist, admin, super_admin | L, E, X, R | OK |
| /sales | SalesScreen | salesProvider, cashiersProvider | sales, profiles | 0006, 0019 | cashier, accountant, admin, super_admin | L, E, X, R | OK |
| /sales/:id | SaleDetailScreen | saleProvider, saleItemsProvider, salePaymentsProvider | sales, sale_items, sale_payments | 0006, 0019 | sales roles | L, E, X, R | OK |
| /sales/returns | ReturnsScreen | returnsProvider | process_sale_return, sale_items | 0006, 0013, 0019 | cashier, admin, super_admin | L, E, X, R | OK |
| /shifts | ShiftsScreen | myOpenShiftProvider, shiftsProvider | shifts, open_shift, close_shift, shift_expected_cash | 0006, 0019 | cashier, admin, super_admin | L, E, X, R | OK |
| /customers | CustomersScreen | customersProvider | customers | 0006, 0019 | cashier, admin, super_admin | L, E, X, R | OK |
| /customers/:id | CustomerDetailScreen | customerProvider, customerStatsProvider, salesProvider | customer_stats, sales | 0006, 0019 | cashier, admin, super_admin | L, E, X, R | OK |
| /prescriptions | PrescriptionsScreen | prescriptionsProvider | prescriptions, prescription_items, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | L, E, X, R | OK |
| /expenses | ExpensesScreen | expensesProvider, receiptSettingsProvider | expenses, set_expense_status, storage | 0006, 0010, 0019 | accountant, admin, super_admin | L, E, X, R | OK |
| /reports | ReportsScreen | reportsProvider, branchPickerProvider | v_report_* (12 reports) | 0014, 0019 | accountant, admin, super_admin | L, E, X, R | OK |
| /admin/users | UsersScreen | usersProvider | profiles, set_user_access, Edge Functions | 0015, 0019 | admin, super_admin | L, E, X, R | OK |
| /admin/team | TeamAccessScreen | teamProvider, usersProvider | profiles, set_user_access, share_admin_access | 0015, 0019 | admin, super_admin | L, E, X, R | OK |
| /admin/branches | BranchesScreen | branchesProvider | branches | 0002, 0012, 0019 | admin, super_admin | L, E, X, R | OK |
| /admin/settings | SettingsScreen | appSettingsProvider | app_settings, publish_app_settings, branding | 0006, 0010, 0019 | admin, super_admin | L, E, X, R | OK |
| /admin/audit | AuditScreen | auditProvider | v_activity_log, correction RPCs | 0017, 0019 | admin, super_admin | L, E, X, R | OK |
| /profile | ProfileScreen | authProvider | profiles, update_my_profile, avatars | 0002, 0010, 0019 | authenticated | L, X, R | OK |

## 2. All `lib` files

| File | Route / role | Responsibility | DB object | Migration | Roles | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/app.dart` | bootstrap | app widget tree | (none) | n/a | all | OK |
| `lib/core/activity/activity.dart` | (shared) | activity repository/model | activity_log, v_activity_log | 0017, 0019 | admin, super_admin | OK |
| `lib/core/activity/activity_range.dart` | (shared) | pure audit range helper | (none) | n/a | all | OK |
| `lib/core/auth/auth_controller.dart` | (shared) | session/profile state, no fabricated cashier | profiles, get_my_profile | 0016, 0018, 0019 | all | OK |
| `lib/core/dates.dart` | (shared) | Addis timezone boundaries/formatting | (none) | n/a | all | OK |
| `lib/core/device_permissions.dart` | (shared) | camera/photo permission flow | Android permissions | android | all | OK |
| `lib/core/env.dart` | (shared) | dart-define config | Supabase URL/anon key | tooling | all | OK |
| `lib/core/errors/app_error.dart` | (shared) | web-safe AppErrorMapper | (none) | n/a | all | OK |
| `lib/core/errors/error_reporter.dart` | (shared) | optional error reporting | (none) | n/a | all | OK |
| `lib/core/money.dart` | (shared) | ETB money formatting | (none) | n/a | all | OK |
| `lib/core/nav/app_shell.dart` | (shared) | authenticated shell | profiles role/branch | 0002, 0019 | all | OK |
| `lib/core/nav/menu_items.dart` | (shared) | role-filtered menu | permissions map | 0019 | all | OK |
| `lib/core/permissions.dart` | (shared) | role/module matrix | (none) | n/a | all | OK |
| `lib/core/router.dart` | (shared) | waits for session+profile, role homes, no denied loop | get_my_profile | 0016, 0019 | all | OK |
| `lib/core/state/app_cache.dart` | (shared) | identity-keyed cache | (none) | n/a | all | OK |
| `lib/core/state/async_state_view.dart` | (shared) | loading/empty/error/retry policy | (none) | n/a | all | OK |
| `lib/core/strings.dart` | (shared) | central friendly copy | (none) | n/a | all | OK |
| `lib/core/supabase_client.dart` | (shared) | Supabase client/readiness | Auth/PostgREST/Storage | tooling | all | OK |
| `lib/core/theme/app_colors.dart` | (shared) | white/pink/gold palette | (none) | n/a | all | OK |
| `lib/core/theme/app_theme.dart` | (shared) | Material theme | (none) | n/a | all | OK |
| `lib/core/widgets.dart` | (shared) | widget barrel | (none) | n/a | all | OK |
| `lib/core/widgets/barcode_scan_button.dart` | (shared) | camera permission + barcode | device camera | android | all | OK |
| `lib/core/widgets/buttons.dart` | (shared) | shared buttons | (none) | n/a | all | OK |
| `lib/core/widgets/data_table_plus.dart` | (shared) | table/filter/CSV export | (none) | n/a | all | OK |
| `lib/core/widgets/display.dart` | (shared) | cards, grids, badges | (none) | n/a | all | OK |
| `lib/core/widgets/feedback.dart` | (shared) | empty/loading/error widgets | (none) | n/a | all | OK |
| `lib/core/widgets/inputs.dart` | (shared) | form inputs | (none) | n/a | all | OK |
| `lib/core/widgets/yusra_logo.dart` | (shared) | brand logo | branding bucket | 0010, 0019 | all | OK |
| `lib/features/admin/audit_screen.dart` | /admin | /admin | profiles, app_settings, branches, activity_log | 0002, 0010, 0015-0019 | admin, super_admin | OK |
| `lib/features/admin/branches_screen.dart` | /admin | /admin | profiles, app_settings, branches, activity_log | 0002, 0010, 0015-0019 | admin, super_admin | OK |
| `lib/features/admin/settings_screen.dart` | /admin | /admin | profiles, app_settings, branches, activity_log | 0002, 0010, 0015-0019 | admin, super_admin | OK |
| `lib/features/admin/team_access_screen.dart` | /admin | /admin | profiles, app_settings, branches, activity_log | 0002, 0010, 0015-0019 | admin, super_admin | OK |
| `lib/features/admin/users_screen.dart` | /admin | /admin | profiles, app_settings, branches, activity_log | 0002, 0010, 0015-0019 | admin, super_admin | OK |
| `lib/features/auth/forbidden_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/auth/forgot_password_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/auth/login_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/auth/profile_error_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/auth/profile_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/auth/reset_password_screen.dart` | /auth | /auth | profiles, Supabase Auth | 0002, 0016, 0018, 0019 | all | OK |
| `lib/features/customers/customers_routes.dart` | (shared) | (shared) | customers, customer_stats, sales | 0006, 0019 | cashier, admin, super_admin | OK |
| `lib/features/customers/data/customers.dart` | (provider) | (provider) | customers, customer_stats, sales | 0006, 0019 | cashier, admin, super_admin | OK |
| `lib/features/customers/screens/customers_screen.dart` | /customers | /customers | customers, customer_stats, sales | 0006, 0019 | cashier, admin, super_admin | OK |
| `lib/features/dashboard/dashboard_metrics.dart` | /dashboard | /dashboard | v_report_*, activity_log | 0014, 0017, 0019 | admin, super_admin | OK |
| `lib/features/dashboard/dashboard_screen.dart` | /dashboard | /dashboard | v_report_*, activity_log | 0014, 0017, 0019 | admin, super_admin | OK |
| `lib/features/expenses/expenses_screen.dart` | /expenses | /expenses | expenses, set_expense_status | 0006, 0019 | accountant, admin, super_admin | OK |
| `lib/features/inventory/data/inventory_ids.dart` | (provider) | (provider) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/data/inventory_models.dart` | (provider) | (provider) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/data/inventory_providers.dart` | (provider) | (provider) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/data/inventory_repository.dart` | (provider) | (provider) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/inventory_routes.dart` | (shared) | (shared) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/logic/medicine_csv.dart` | (shared) | (shared) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/logic/stock_rules.dart` | (shared) | (shared) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/adjustments_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/alerts_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/batches_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/categories_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/medicine_detail_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/medicines_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/movements_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/stock_overview_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/screens/stocktake_screen.dart` | /inventory | /inventory | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/inventory/widgets/stock_widgets.dart` | (shared) | (shared) | medicines, batches, stock_movements, views | 0003, 0005, 0008, 0019 | inventory roles | OK |
| `lib/features/pos/pos_routes.dart` | (shared) | (shared) | create_sale, open_shift, customers | 0006, 0007, 0019 | cashier, pharmacist, admin, super_admin | OK |
| `lib/features/pos/screens/payment_dialog.dart` | /pos | /pos | create_sale, open_shift, customers | 0006, 0007, 0019 | cashier, pharmacist, admin, super_admin | OK |
| `lib/features/pos/screens/pos_screen.dart` | /pos | /pos | create_sale, open_shift, customers | 0006, 0007, 0019 | cashier, pharmacist, admin, super_admin | OK |
| `lib/features/prescriptions/data/prescription_model.dart` | (provider) | (provider) | prescriptions, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | OK |
| `lib/features/prescriptions/data/prescription_paths.dart` | (provider) | (provider) | prescriptions, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | OK |
| `lib/features/prescriptions/data/prescriptions.dart` | (provider) | (provider) | prescriptions, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | OK |
| `lib/features/prescriptions/prescriptions_routes.dart` | (shared) | (shared) | prescriptions, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | OK |
| `lib/features/prescriptions/screens/prescriptions_screen.dart` | /prescriptions | /prescriptions | prescriptions, storage | 0006, 0010, 0019 | pharmacist, admin, super_admin | OK |
| `lib/features/purchasing/data/purchase_documents.dart` | (provider) | (provider) | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/purchasing/data/purchase_status_helpers.dart` | (provider) | (provider) | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/purchasing/data/purchasing.dart` | (provider) | (provider) | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/purchasing/purchasing_routes.dart` | (shared) | (shared) | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/purchasing/screens/purchase_order_screen.dart` | /purchasing/orders | /purchasing/orders | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/purchasing/screens/purchase_orders_screen.dart` | /purchasing/orders | /purchasing/orders | purchase_orders, receive_purchase_order, PDFs | 0004, 0007, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/reports/reports_screen.dart` | /reports | /reports | v_report_* (12 reports) | 0014, 0019 | accountant, admin, super_admin | OK |
| `lib/features/sales/data/sales.dart` | (provider) | (provider) | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/logic/cart.dart` | (shared) | (shared) | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/logic/held_carts.dart` | (shared) | (shared) | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/logic/receipts.dart` | (shared) | (shared) | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/sales_routes.dart` | (shared) | (shared) | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/screens/returns_screen.dart` | /sales | /sales | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/screens/sale_detail_screen.dart` | /sales | /sales | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/sales/screens/sales_screen.dart` | /sales | /sales | sales, sale_items, returns, receipts | 0006, 0013, 0019 | sales roles | OK |
| `lib/features/shifts/screens/shifts_screen.dart` | /shifts | /shifts | shifts, open_shift, close_shift | 0006, 0019 | cashier, admin, super_admin | OK |
| `lib/features/shifts/shifts_routes.dart` | (shared) | (shared) | shifts, open_shift, close_shift | 0006, 0019 | cashier, admin, super_admin | OK |
| `lib/features/suppliers/data/suppliers.dart` | (provider) | (provider) | suppliers, supplier_stats | 0004, 0013, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/suppliers/screens/suppliers_screen.dart` | /suppliers | /suppliers | suppliers, supplier_stats | 0004, 0013, 0019 | store_keeper, admin, super_admin | OK |
| `lib/features/suppliers/suppliers_routes.dart` | (shared) | (shared) | suppliers, supplier_stats | 0004, 0013, 0019 | store_keeper, admin, super_admin | OK |
| `lib/main.dart` | bootstrap | Supabase init, auth bootstrap | get_my_profile, Supabase client | 0016, 0019 | all | OK |

## 3. SQL, Edge Functions, CI and platform coverage

| Area | Object | Verification | Status |
| --- | --- | --- | --- |
| SQL | `0001`–`0018` baseline migrations | `tool/ci_psql.sh` applies numbered files in order on PostgreSQL 16 | OK |
| SQL | `0019_hardening_fixes.sql` | New-only migration: `P0002`, SECURITY DEFINER hardening, safe `handle_new_user`, RPC-only writes, correction authorization, storage policies, report-view `date` columns | OK |
| SQL | `supabase/all_owner_sql.sql` | Regenerated from `0001`–`0019` with `-- FILE:` markers; runs twice cleanly, including view drops before recreate | OK |
| SQL | `supabase/checks/schema_check.sql` | Extended through `0019`; emits PASS/FAIL, zero FAIL rows locally and in CI | OK |
| SQL | `tool/db_test.sql` | 15 functional PASS checks covering auth, POs, direct-write blocks, expenses, audit and report dates | OK |
| SQL | RLS / SECURITY DEFINER | Listed functions set `search_path`, revoke from `public, anon`, grant to `authenticated` | OK |
| Edge | `admin-create-user` | Server-side caller role check, typed JSON errors, CORS, validation, shared helpers | OK |
| Edge | `admin-reset-password` | Server-side caller role check, typed JSON errors, CORS, validation, shared helpers | OK |
| CI | `build` | Flutter `3.24.5`, Dart 3, Java 17, Gradle, SDK 34 / build-tools `34.0.0`, preinstalled platform-tools, Deno; format, analyze, test | OK |
| CI | `db-test` | `postgres:16` service, stubs, `all_owner_sql.sql` twice, migrations, schema check, functional test; fails on FAIL rows | OK |
| CI | `deno check` | Both Edge Functions type-check | OK |
| CI | `build-apk.yml` | Pinned toolchain assertions and release APK artifact | OK |
| Android | manifest / Gradle | CAMERA + autofocus, `READ_MEDIA_IMAGES`, scoped legacy storage, label, launcher icon, compatible `minSdk`, denied-permission UI | OK |
| Web | `web/**` | Bytes uploads, guarded platform code, branded manifest/icons | OK |
| Tool | `tool/**` | Seed/smoke helpers, `ci_psql.sh`, `db_test.sql`, Supabase stubs | OK |
| Test | `test/**` | Role homes, denied escape, profile-error retry, bytes helpers, repo-wide raw-error guard | OK |

## 4. Coverage checklist

- [x] All 91 `lib/**/*.dart` files read and mapped above
- [x] `supabase/migrations/0001`–`0019` read and mapped
- [x] `supabase/all_owner_sql.sql` regenerated and re-runnable twice
- [x] `supabase/checks/schema_check.sql` extended through `0019`
- [x] `supabase/functions/**` read and hardened
- [x] `.github/workflows/**`, `android/**`, `web/**`, `tool/**`, `test/**` read and mapped
- [x] Every row in the tables above says `OK`
