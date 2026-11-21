-- Yusra Pharmacy — schema verification (0001 through 0019).
-- Run with the Supabase SQL Editor after applying 0019_hardening_fixes.sql.
-- Every row has a kind, object name, status of PASS or FAIL, and a FIX hint
-- (blank for PASS). The db-test CI job fails on any non-PASS row.
-- v_expired_batches is intentionally not required: the screen derives the same
-- figures directly from stock_batches.

with expected_tables(name) as (
  values ('branches'), ('profiles'), ('app_settings'), ('doc_counters'), ('audit_logs'),
         ('categories'), ('medicines'), ('suppliers'), ('purchase_orders'),
         ('purchase_order_items'), ('stock_batches'), ('stock_movements'),
         ('customers'), ('prescriptions'), ('shifts'), ('sales'), ('sale_items'),
         ('sale_payments'), ('sale_returns'), ('sale_return_items'), ('expenses'),
         ('activity_log')
),
expected_views(name) as (
  values ('v_stock_summary'), ('v_low_stock'), ('v_expiring_batches'), ('v_daily_sales'),
         ('v_report_sales_by_day'), ('v_report_sales_by_cashier'),
         ('v_report_sales_payment'), ('v_report_sales_by_medicine'),
         ('v_report_profit'), ('v_report_stock_valuation'),
         ('v_report_expiry_losses'), ('v_report_purchases_supplier'),
         ('v_report_expenses'), ('v_report_net_profit'),
         ('v_report_shift_variance'), ('v_report_controlled_register')
),
expected_functions(name, nargs) as (
  values ('set_updated_at', 0), ('my_role', 0), ('my_branch', 0),
         ('has_role', 1), ('can_access_branch', 1), ('handle_new_user', 0),
         ('next_doc_no', 2), ('add_stock_batch', 7), ('adjust_stock', 4),
         ('receive_purchase_order', 2), ('open_shift', 2), ('close_shift', 3),
         ('create_sale', 8), ('void_sale', 2), ('process_sale_return', 4),
         ('set_user_access', 4), ('share_admin_access', 1),
         ('publish_app_settings', 0), ('get_my_profile', 0),
         ('request_activity_correction', 2), ('approve_activity_correction', 1),
         ('update_my_profile', 3), ('set_purchase_order_status', 2),
         ('approve_purchase_order', 1), ('cancel_purchase_order', 1),
         ('set_expense_status', 2), ('approve_expense', 1), ('reject_expense', 1),
         ('customer_stats', 1), ('shift_expected_cash', 1),
         ('trg_po_defaults', 0), ('trg_rx_defaults', 0), ('trg_po_total', 0),
         ('recalc_po_subtotal', 0), ('guard_po_status', 0),
         ('guard_po_receipt', 0), ('guard_expense_status', 0),
         ('protect_profile_fields', 0), ('audit_row', 0)
),
expected_triggers(name) as (
  values ('on_auth_user_created'), ('trg_branches_updated'), ('trg_profiles_updated'),
         ('trg_categories_updated'), ('trg_medicines_updated'), ('trg_suppliers_updated'),
         ('trg_purchase_orders_updated'), ('trg_stock_batches_updated'),
         ('trg_customers_updated'), ('trg_prescriptions_updated'),
         ('trg_sales_updated'), ('trg_expenses_updated'),
         ('trg_po_numbering'), ('trg_rx_numbering'), ('trg_po_total_calc'),
         ('trg_poi_recalc'), ('trg_po_guard'), ('trg_poi_receipt_guard'),
         ('trg_expense_status_guard'), ('trg_profiles_protect'),
         ('trg_branches_audit'), ('trg_profiles_audit'), ('trg_sales_audit'),
         ('activity_branches'), ('activity_profiles'), ('activity_stock'),
         ('activity_po'), ('activity_sales'), ('activity_returns'),
         ('activity_expenses'), ('activity_shifts'), ('activity_customers'),
         ('activity_prescriptions')
),
expected_policies(name) as (
  values ('rls_branches_read'), ('rls_profiles_read'), ('rls_settings_read'),
         ('rls_audit_read'), ('rls_categories_read'), ('rls_medicines_read'),
         ('rls_suppliers_read'), ('rls_customers_read'), ('rls_po_read'),
         ('rls_poi_read'), ('rls_batches_read'), ('rls_movements_read'),
         ('rls_rx_read'), ('rls_shifts_read'), ('rls_sales_read'),
         ('rls_sale_items_read'), ('rls_sale_payments_read'), ('rls_returns_read'),
         ('rls_return_items_read'), ('rls_expenses_read'), ('rls_categories_write'),
         ('rls_medicines_write'), ('rls_suppliers_write'), ('rls_customers_write'),
         ('rls_settings_write'), ('rls_branches_write'), ('rls_po_write'),
         ('rls_poi_write'), ('rls_rx_write'), ('rls_expenses_write'),
         ('rls_rx_storage_read'), ('rls_rx_storage_write'), ('rls_rx_storage_delete'),
         ('rls_receipts_read'), ('rls_receipts_write'),
         ('rls_avatars_read'), ('rls_avatars_write'), ('rls_avatars_update'), ('rls_avatars_delete'),
         ('rls_branding_read'), ('rls_branding_write'), ('rls_branding_delete'),
         ('rls_medicine_images_read'), ('rls_medicine_images_write'), ('rls_medicine_images_delete')
),
expected_storage_buckets(name, is_public) as (
  values ('prescriptions', false), ('receipts', false), ('branding', true),
         ('avatars', true), ('medicine-images', true)
),
actual_columns as (
  select table_name, array_agg(column_name::text order by column_name) as cols
  from information_schema.columns
  where table_schema = 'public'
  group by table_name
),
results as (
  select 'table'::text as kind, name as object,
         case when to_regclass('public.' || name) is not null then 'PASS' else 'FAIL' end as status,
         'Apply the migration that creates this table (0002..0006, 0017).' as fix
  from expected_tables
  union all
  select 'view', name,
         case when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relname = name and c.relkind in ('v','m'))
              then 'PASS' else 'FAIL' end,
         'Re-run 0008_views.sql / 0014_report_views.sql / 0019_hardening_fixes.sql.'
  from expected_views
  union all
  select 'function', name,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = name and p.pronargs = nargs)
              then 'PASS' else 'FAIL' end,
         'Apply the migration defining this function (through 0019_hardening_fixes.sql).'
  from expected_functions
  union all
  select 'trigger', name,
         case when exists (select 1 from pg_trigger where tgname = name and not tgisinternal)
              then 'PASS' else 'FAIL' end,
         'Re-run 0009_triggers.sql / 0017_activity_audit.sql / 0019_hardening_fixes.sql.'
  from expected_triggers
  union all
  select 'policy', name,
         case when exists (select 1 from pg_policy where polname = name)
              then 'PASS' else 'FAIL' end,
         'Re-run 0012_rls_hardening.sql / 0019_hardening_fixes.sql.'
  from expected_policies
  union all
  select 'storage_bucket', b.name,
         case when exists (select 1 from storage.buckets s
                            where s.id = b.name and s.public = b.is_public)
              then 'PASS' else 'FAIL' end,
         'Re-run 0012_rls_hardening.sql / 0019_hardening_fixes.sql.'
  from expected_storage_buckets b
  union all
  select 'setting', 'app_settings.max_cashier_discount_pct',
         case when exists (select 1 from app_settings where key = 'max_cashier_discount_pct')
              then 'PASS' else 'FAIL' end,
         'Re-run 0011_seed.sql.'
  union all
  select 'column_group', 'sales.money',
         case when (select cols from actual_columns where table_name = 'sales')
               @> array['subtotal','discount','tax','total','paid','change_due']::text[]
              then 'PASS' else 'FAIL' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'column_group', 'stock_batches.core',
         case when (select cols from actual_columns where table_name = 'stock_batches')
               @> array['branch_id','medicine_id','batch_no','expiry_date','quantity','cost_price']::text[]
              then 'PASS' else 'FAIL' end,
         'Re-run 0005_stock.sql.'
  union all
  select 'column_group', 'sale_items.core',
         case when (select cols from actual_columns where table_name = 'sale_items')
               @> array['sale_id','medicine_id','batch_id','quantity','unit_price','line_total','returned_qty']::text[]
              then 'PASS' else 'FAIL' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'column_group', 'shifts.cash',
         case when (select cols from actual_columns where table_name = 'shifts')
               @> array['branch_id','cashier_id','opening_cash','expected_cash','closing_cash','difference','status']::text[]
              then 'PASS' else 'FAIL' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'column_group', 'expenses.status',
         case when (select cols from actual_columns where table_name = 'expenses')
               @> array['status']::text[]
              then 'PASS' else 'FAIL' end,
         'Apply 0019_hardening_fixes.sql.'
  union all
  select 'report_dates', name,
         case when exists (
           select 1 from information_schema.columns c
           where c.table_schema = 'public' and c.table_name = name and c.column_name = 'date')
              then 'PASS' else 'FAIL' end,
         'Apply 0019_hardening_fixes.sql (uniform date column).'
  from expected_views
  where name like 'v_report_%'
  union all
  select 'security', 'security_definer.search_path',
         case when not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=public%')
              then 'PASS' else 'FAIL' end,
         'Apply 0019_hardening_fixes.sql.'
  union all
  select 'security', 'security_definer.execute_grants',
         case when not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosecdef
             and (coalesce(p.proacl::text, '') like '={X}/%'
                  or coalesce(p.proacl::text, '') like '%,anon=X%'
                  or coalesce(p.proacl::text, '') not like '%authenticated=X%'))
              then 'PASS' else 'FAIL' end,
         'Apply 0019_hardening_fixes.sql.'
  union all
  select 'security', 'no_PGRST116_in_sql',
         case when not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prosrc ilike '%PGRST116%')
              then 'PASS' else 'FAIL' end,
         'Apply 0019_hardening_fixes.sql.'
  union all
  select 'rls', t.name,
         case when c.relrowsecurity then 'PASS' else 'FAIL' end,
         'Re-run 0012_rls_hardening.sql to enable RLS on ' || t.name || '.'
  from expected_tables t
  left join pg_class c on c.oid = to_regclass('public.' || t.name)
)
select kind, object, status,
       case when status = 'FAIL' then fix else '' end as fix
from results
order by kind, object;
