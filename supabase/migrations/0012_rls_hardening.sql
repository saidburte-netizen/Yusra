-- 0012 — Proposed RLS + Storage hardening (NOT YET APPLIED — owner review required).
--
-- The owner's original 11 steps did not include RLS policies or Storage
-- buckets. This file is written to the change protocol in supabase/README.md:
-- it is additive and idempotent, changes no table structure, and must be
-- run once by the owner in the Supabase SQL Editor before the smoke test can
-- pass. It is safe to run twice.
--
-- RUN IN SUPABASE SQL EDITOR — purpose: enable row level security on every
-- application table, grant only the reads and writes each role needs, and
-- create the private `prescriptions` Storage bucket with branch-scoped access.

-- ---------------------------------------------------------------------------
-- Enable RLS. Tables with no policy below are closed to anon/authenticated by
-- default; all writes to stock, sales and shifts go through SECURITY DEFINER
-- RPCs, which bypass RLS by design.
-- ---------------------------------------------------------------------------
alter table branches            enable row level security;
alter table profiles            enable row level security;
alter table app_settings        enable row level security;
alter table doc_counters        enable row level security;
alter table audit_logs          enable row level security;
alter table categories          enable row level security;
alter table medicines           enable row level security;
alter table suppliers           enable row level security;
alter table purchase_orders     enable row level security;
alter table purchase_order_items enable row level security;
alter table stock_batches       enable row level security;
alter table stock_movements     enable row level security;
alter table customers           enable row level security;
alter table prescriptions       enable row level security;
alter table shifts              enable row level security;
alter table sales               enable row level security;
alter table sale_items          enable row level security;
alter table sale_payments       enable row level security;
alter table sale_returns        enable row level security;
alter table sale_return_items   enable row level security;
alter table expenses            enable row level security;

-- ---------------------------------------------------------------------------
-- Shared reads
-- ---------------------------------------------------------------------------
drop policy if exists rls_branches_read on branches;
create policy rls_branches_read on branches for select to authenticated using (true);

drop policy if exists rls_profiles_read on profiles;
create policy rls_profiles_read on profiles for select to authenticated
using (id = auth.uid() or has_role('super_admin','admin','accountant','pharmacist'));

drop policy if exists rls_settings_read on app_settings;
create policy rls_settings_read on app_settings for select to authenticated using (true);

drop policy if exists rls_audit_read on audit_logs;
create policy rls_audit_read on audit_logs for select to authenticated
using (has_role('super_admin','admin','accountant'));

drop policy if exists rls_categories_read on categories;
create policy rls_categories_read on categories for select to authenticated using (true);

drop policy if exists rls_medicines_read on medicines;
create policy rls_medicines_read on medicines for select to authenticated using (true);

drop policy if exists rls_suppliers_read on suppliers;
create policy rls_suppliers_read on suppliers for select to authenticated using (true);

drop policy if exists rls_customers_read on customers;
create policy rls_customers_read on customers for select to authenticated using (true);

-- Branch-scoped reads for operational tables.
drop policy if exists rls_po_read on purchase_orders;
create policy rls_po_read on purchase_orders for select to authenticated
using (can_access_branch(branch_id));

drop policy if exists rls_poi_read on purchase_order_items;
create policy rls_poi_read on purchase_order_items for select to authenticated
using (exists (select 1 from purchase_orders po where po.id = po_id and can_access_branch(po.branch_id)));

drop policy if exists rls_batches_read on stock_batches;
create policy rls_batches_read on stock_batches for select to authenticated
using (can_access_branch(branch_id));

drop policy if exists rls_movements_read on stock_movements;
create policy rls_movements_read on stock_movements for select to authenticated
using (can_access_branch(branch_id));

drop policy if exists rls_rx_read on prescriptions;
create policy rls_rx_read on prescriptions for select to authenticated
using (can_access_branch(branch_id));

drop policy if exists rls_shifts_read on shifts;
create policy rls_shifts_read on shifts for select to authenticated
using (can_access_branch(branch_id) and (has_role('super_admin','admin','accountant','pharmacist') or cashier_id = auth.uid()));

drop policy if exists rls_sales_read on sales;
create policy rls_sales_read on sales for select to authenticated
using (can_access_branch(branch_id) and (has_role('super_admin','admin','accountant','pharmacist') or cashier_id = auth.uid()));

drop policy if exists rls_sale_items_read on sale_items;
create policy rls_sale_items_read on sale_items for select to authenticated
using (exists (select 1 from sales s where s.id = sale_id and can_access_branch(s.branch_id)
       and (has_role('super_admin','admin','accountant','pharmacist') or s.cashier_id = auth.uid())));

drop policy if exists rls_sale_payments_read on sale_payments;
create policy rls_sale_payments_read on sale_payments for select to authenticated
using (exists (select 1 from sales s where s.id = sale_id and can_access_branch(s.branch_id)
       and (has_role('super_admin','admin','accountant','pharmacist') or s.cashier_id = auth.uid())));

drop policy if exists rls_returns_read on sale_returns;
create policy rls_returns_read on sale_returns for select to authenticated
using (can_access_branch(branch_id) and
       (has_role('super_admin','admin','accountant','pharmacist') or processed_by = auth.uid()));

drop policy if exists rls_return_items_read on sale_return_items;
create policy rls_return_items_read on sale_return_items for select to authenticated
using (exists (select 1 from sale_returns r where r.id = return_id and can_access_branch(r.branch_id)
       and (has_role('super_admin','admin','accountant','pharmacist') or r.processed_by = auth.uid())));

drop policy if exists rls_expenses_read on expenses;
create policy rls_expenses_read on expenses for select to authenticated
using (can_access_branch(branch_id));

-- ---------------------------------------------------------------------------
-- Catalogue writes — cashiers have no write policy, so direct INSERTs fail.
-- ---------------------------------------------------------------------------
drop policy if exists rls_categories_write on categories;
create policy rls_categories_write on categories for all to authenticated
using (has_role('super_admin','admin','pharmacist')) with check (has_role('super_admin','admin','pharmacist'));

drop policy if exists rls_medicines_write on medicines;
create policy rls_medicines_write on medicines for all to authenticated
using (has_role('super_admin','admin','pharmacist')) with check (has_role('super_admin','admin','pharmacist'));

drop policy if exists rls_suppliers_write on suppliers;
create policy rls_suppliers_write on suppliers for all to authenticated
using (has_role('super_admin','admin','pharmacist','store_keeper')) with check (has_role('super_admin','admin','pharmacist','store_keeper'));

drop policy if exists rls_customers_write on customers;
create policy rls_customers_write on customers for all to authenticated
using (has_role('super_admin','admin','pharmacist','cashier')) with check (has_role('super_admin','admin','pharmacist','cashier'));

drop policy if exists rls_settings_write on app_settings;
create policy rls_settings_write on app_settings for all to authenticated
using (has_role('super_admin','admin')) with check (has_role('super_admin','admin'));

drop policy if exists rls_branches_write on branches;
create policy rls_branches_write on branches for all to authenticated
using (has_role('super_admin','admin')) with check (has_role('super_admin','admin'));

drop policy if exists rls_po_write on purchase_orders;
create policy rls_po_write on purchase_orders for all to authenticated
using (can_access_branch(branch_id) and has_role('super_admin','admin','pharmacist','store_keeper'))
with check (can_access_branch(branch_id) and has_role('super_admin','admin','pharmacist','store_keeper'));

drop policy if exists rls_poi_write on purchase_order_items;
create policy rls_poi_write on purchase_order_items for all to authenticated
using (exists (select 1 from purchase_orders po where po.id = po_id and can_access_branch(po.branch_id) and has_role('super_admin','admin','pharmacist','store_keeper')))
with check (exists (select 1 from purchase_orders po where po.id = po_id and can_access_branch(po.branch_id) and has_role('super_admin','admin','pharmacist','store_keeper')));

drop policy if exists rls_rx_write on prescriptions;
create policy rls_rx_write on prescriptions for all to authenticated
using (can_access_branch(branch_id) and has_role('super_admin','admin','pharmacist'))
with check (can_access_branch(branch_id) and has_role('super_admin','admin','pharmacist'));

drop policy if exists rls_expenses_write on expenses;
create policy rls_expenses_write on expenses for all to authenticated
using (can_access_branch(branch_id) and has_role('super_admin','admin','accountant'))
with check (can_access_branch(branch_id) and has_role('super_admin','admin','accountant'));

-- No INSERT/UPDATE/DELETE policies on: profiles, stock_batches, stock_movements,
-- shifts, sales, sale_items, sale_payments, sale_returns, sale_return_items,
-- audit_logs, doc_counters. Those are written only by SECURITY DEFINER RPCs
-- and triggers, which is what makes the smoke-test role rules enforceable.

-- ---------------------------------------------------------------------------
-- RPC execute grants. SECURITY DEFINER functions must not be callable by anon.
-- ---------------------------------------------------------------------------
revoke execute on function add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) from anon;
revoke execute on function adjust_stock(uuid, int, movement_type, text) from anon;
revoke execute on function receive_purchase_order(uuid, jsonb) from anon;
revoke execute on function open_shift(uuid, numeric) from anon;
revoke execute on function close_shift(uuid, numeric, text) from anon;
revoke execute on function create_sale(uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text) from anon;

grant execute on function add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) to authenticated;
grant execute on function adjust_stock(uuid, int, movement_type, text) to authenticated;
grant execute on function receive_purchase_order(uuid, jsonb) to authenticated;
grant execute on function open_shift(uuid, numeric) to authenticated;
grant execute on function close_shift(uuid, numeric, text) to authenticated;
grant execute on function create_sale(uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text) to authenticated;

-- void_sale / process_sale_return are added by 0013_rpc_gaps.sql (owner must
-- run that file first). Their grants live there so 0012 stays runnable alone.

-- ---------------------------------------------------------------------------
-- Private Storage bucket for prescription images: <branch_id>/<rx_id>/<file>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('prescriptions', 'prescriptions', false, 5242880)
on conflict (id) do nothing;

drop policy if exists rls_rx_storage_read on storage.objects;
create policy rls_rx_storage_read on storage.objects for select to authenticated
using (bucket_id = 'prescriptions' and (
  has_role('super_admin','admin','pharmacist') or
  (storage.foldername(name))[1] = coalesce(my_branch()::text, '')
));

drop policy if exists rls_rx_storage_write on storage.objects;
create policy rls_rx_storage_write on storage.objects for insert to authenticated
with check (bucket_id = 'prescriptions' and has_role('super_admin','admin','pharmacist')
  and (storage.foldername(name))[1] = coalesce(my_branch()::text, ''));

drop policy if exists rls_rx_storage_delete on storage.objects;
create policy rls_rx_storage_delete on storage.objects for delete to authenticated
using (bucket_id = 'prescriptions' and has_role('super_admin','admin','pharmacist'));
