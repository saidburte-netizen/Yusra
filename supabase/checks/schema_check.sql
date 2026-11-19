-- Yusra Pharmacy — schema verification.
-- Run once in the Supabase SQL Editor after applying the migrations.
-- Every row has a kind, an object name and a status of PASS or MISSING.
-- The owner sends the full result to Agent C. No MISSING rows are expected
-- after 0001..0013 have been applied (0012 and 0013 are still proposed).

with expected_tables(name) as (
  values ('branches'), ('profiles'), ('app_settings'), ('doc_counters'), ('audit_logs'),
         ('categories'), ('medicines'), ('suppliers'), ('purchase_orders'),
         ('purchase_order_items'), ('stock_batches'), ('stock_movements'),
         ('customers'), ('prescriptions'), ('shifts'), ('sales'), ('sale_items'),
         ('sale_payments'), ('sale_returns'), ('sale_return_items'), ('expenses')
),
expected_views(name) as (
  values ('v_stock_summary'), ('v_low_stock'), ('v_expiring_batches'), ('v_daily_sales')
),
expected_functions(name, nargs) as (
  values ('set_updated_at', 0), ('my_role', 0), ('my_branch', 0),
         ('has_role', 1), ('can_access_branch', 1), ('handle_new_user', 0),
         ('next_doc_no', 2), ('add_stock_batch', 7), ('adjust_stock', 4),
         ('receive_purchase_order', 2), ('open_shift', 2), ('close_shift', 3),
         ('create_sale', 8), ('void_sale', 2), ('process_sale_return', 4),
         ('trg_po_defaults', 0), ('trg_rx_defaults', 0), ('trg_po_total', 0),
         ('recalc_po_subtotal', 0), ('guard_po_status', 0),
         ('protect_profile_fields', 0), ('audit_row', 0)
),
expected_triggers(name) as (
  values ('on_auth_user_created'), ('trg_branches_updated'), ('trg_profiles_updated'),
         ('trg_categories_updated'), ('trg_medicines_updated'), ('trg_suppliers_updated'),
         ('trg_purchase_orders_updated'), ('trg_stock_batches_updated'),
         ('trg_customers_updated'), ('trg_prescriptions_updated'),
         ('trg_sales_updated'), ('trg_expenses_updated'),
         ('trg_po_numbering'), ('trg_rx_numbering'), ('trg_po_total_calc'),
         ('trg_poi_recalc'), ('trg_po_guard'), ('trg_profiles_protect'),
         ('trg_branches_audit'), ('trg_profiles_audit'), ('trg_sales_audit')
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
         ('rls_rx_storage_read'), ('rls_rx_storage_write'), ('rls_rx_storage_delete')
),
actual_columns as (
  select table_name, array_agg(column_name order by column_name) as cols
  from information_schema.columns
  where table_schema = 'public'
  group by table_name
),
results as (
  select 'table'::text as kind, name as object,
         case when to_regclass('public.' || name) is not null then 'PASS' else 'MISSING' end as status
  from expected_tables
  union all
  select 'view', name,
         case when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                           where n.nspname = 'public' and c.relname = name and c.relkind in ('v','m'))
              then 'PASS' else 'MISSING' end
  from expected_views
  union all
  select 'function', name,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.proname = name and p.pronargs = nargs)
              then 'PASS' else 'MISSING' end
  from expected_functions
  union all
  select 'trigger', name,
         case when exists (select 1 from pg_trigger where tgname = name and not tgisinternal)
              then 'PASS' else 'MISSING' end
  from expected_triggers
  union all
  select 'policy', name,
         case when exists (select 1 from pg_policy where polname = name)
              then 'PASS' else 'MISSING' end
  from expected_policies
  union all
  select 'storage_bucket', 'prescriptions',
         case when exists (select 1 from storage.buckets where id = 'prescriptions' and not public)
              then 'PASS' else 'MISSING' end
  union all
  select 'column_group', 'sales.money',
         case when (select cols from actual_columns where table_name = 'sales')
              @> array['subtotal','discount','tax','total','paid','change_due']::text[]
              then 'PASS' else 'MISSING' end
  union all
  select 'column_group', 'stock_batches.core',
         case when (select cols from actual_columns where table_name = 'stock_batches')
              @> array['branch_id','medicine_id','batch_no','expiry_date','quantity','cost_price']::text[]
              then 'PASS' else 'MISSING' end
  union all
  select 'column_group', 'sale_items.core',
         case when (select cols from actual_columns where table_name = 'sale_items')
              @> array['sale_id','medicine_id','batch_id','quantity','unit_price','line_total','returned_qty']::text[]
              then 'PASS' else 'MISSING' end
  union all
  select 'column_group', 'shifts.cash',
         case when (select cols from actual_columns where table_name = 'shifts')
              @> array['branch_id','cashier_id','opening_cash','expected_cash','closing_cash','difference','status']::text[]
              then 'PASS' else 'MISSING' end
)
select kind, object, status from results
union all
select 'rls', t.name,
       case when c.relrowsecurity then 'PASS' else 'MISSING' end
from expected_tables t
left join pg_class c on c.oid = to_regclass('public.' || t.name)
order by kind, object;
