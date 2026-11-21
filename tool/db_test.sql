-- Functional database test for Yusra Pharmacy (PostgreSQL 16 + Supabase stubs).
-- Applied after all numbered migrations. Verifies the hardening and the RPC
-- workflows the Flutter app depends on. Prints one PASS/FAIL row per check and
-- raises if any check fails, so CI stops on regressions.

create temp table db_test_results (
  test text primary key,
  status text not null check (status in ('PASS', 'FAIL')),
  detail text not null default ''
);

do $$
declare
  v_branch uuid;
  v_admin uuid;
  v_cashier uuid;
  v_other uuid;
  v_target uuid;
  v_supplier uuid;
  v_medicine uuid;
  v_po uuid;
  v_po_item uuid;
  v_expense uuid;
  v_log uuid;
  v_state text;
  v_detail text;
  v_count int;
  -- Sale-return / void regression fixture.
  v_marker text := 'db-test-sale-return-v1';
  v_shift_flow uuid;
  v_sale_flow uuid;
  v_sale_void uuid;
  v_sale_guard uuid;
  v_old_sale uuid;
  v_sale_item uuid;
  v_batch uuid;
  v_return uuid;
  v_refund numeric(14,2);
  v_qty_before int;
  v_qty_after int;
  v_expected_cash numeric(14,2);
begin
  -- -------------------------------------------------------------------------
  -- Fixture: one branch and four staff accounts created through the trigger.
  -- -------------------------------------------------------------------------
  insert into public.branches (name, code)
  values ('DB Test Branch', 'DBTEST')
  on conflict (code) do update set name = excluded.name
  returning id into v_branch;

  insert into auth.users (id, email, raw_app_meta_data)
  values
    ('30000000-0000-0000-0000-000000000001', 'admin@yusra.test',
     '{"role":"super_admin"}'::jsonb),
    ('30000000-0000-0000-0000-000000000002', 'cashier@yusra.test',
     jsonb_build_object('role', 'cashier', 'branch_id', v_branch::text)),
    ('30000000-0000-0000-0000-000000000003', 'other@yusra.test',
     jsonb_build_object('role', 'cashier', 'branch_id', v_branch::text)),
    ('30000000-0000-0000-0000-000000000004', 'target@yusra.test',
     jsonb_build_object('role', 'cashier', 'branch_id', v_branch::text))
  on conflict (id) do update set raw_app_meta_data = excluded.raw_app_meta_data;

  v_admin := '30000000-0000-0000-0000-000000000001';
  v_cashier := '30000000-0000-0000-0000-000000000002';
  v_other := '30000000-0000-0000-0000-000000000003';
  v_target := '30000000-0000-0000-0000-000000000004';

  update public.profiles
     set role = 'super_admin', branch_id = null, is_active = true
   where id = v_admin;
  update public.profiles
     set role = 'cashier', branch_id = v_branch, is_active = true
   where id in (v_cashier, v_other, v_target);

  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- Make the fixture repeatable: remove rows from an earlier run.
  delete from public.stock_movements
   where reference_id = '50000000-0000-0000-0000-000000000001'::uuid;
  delete from public.stock_batches
   where purchase_order_id = '50000000-0000-0000-0000-000000000001'::uuid;
  delete from public.purchase_order_items
   where po_id = '50000000-0000-0000-0000-000000000001'::uuid;
  delete from public.purchase_orders
   where id = '50000000-0000-0000-0000-000000000001'::uuid;

  -- Repeatable cleanup for the sale-return / void fixture below. Sales are
  -- identified by a marker note because create_sale() generates its own id.
  for v_old_sale in
    select id from public.sales where note = v_marker
  loop
    delete from public.stock_movements
     where reference_id = v_old_sale
        or reference_id in (select id from public.sale_returns where sale_id = v_old_sale);
    delete from public.sale_return_items
     where return_id in (select id from public.sale_returns where sale_id = v_old_sale);
    delete from public.sale_returns where sale_id = v_old_sale;
    delete from public.sale_items where sale_id = v_old_sale;
    delete from public.sale_payments where sale_id = v_old_sale;
    delete from public.sales where id = v_old_sale;
  end loop;
  delete from public.shifts
   where cashier_id = v_admin and opening_cash = 100
     and id not in (select shift_id from public.sales where shift_id is not null);

  -- 1. handle_new_user defaults an invalid role to super_admin.
  insert into auth.users (id, email, raw_app_meta_data)
  values ('30000000-0000-0000-0000-000000000009', 'invalid-role@yusra.test',
          '{"role":"definitely_not_a_role"}'::jsonb)
  on conflict (id) do nothing;
  select role::text into v_state from public.profiles
   where id = '30000000-0000-0000-0000-000000000009';
  insert into db_test_results values
    ('handle_new_user_invalid_role_fallback',
     case when v_state = 'super_admin' then 'PASS' else 'FAIL' end,
     coalesce(v_state, 'no profile'));

  -- 2. set_user_access changes access and reports a missing member with P0002.
  perform public.set_user_access(v_target, 'pharmacist'::app_role, v_branch, true);
  select role::text into v_state from public.profiles where id = v_target;
  insert into db_test_results values
    ('set_user_access_updates_role',
     case when v_state = 'pharmacist' then 'PASS' else 'FAIL' end, v_state);

  begin
    perform public.set_user_access(
      '99999999-9999-9999-9999-999999999999'::uuid,
      'cashier'::app_role, v_branch, true);
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('set_user_access_missing_uses_P0002',
     case when v_state = 'P0002' then 'PASS' else 'FAIL' end, v_state);

  -- 3. update_my_profile only touches self-service fields.
  v_detail := public.update_my_profile('Test Admin', '+251911000000', null)->>'full_name';
  insert into db_test_results values
    ('update_my_profile_name',
     case when v_detail = 'Test Admin' then 'PASS' else 'FAIL' end, v_detail);

  -- 4. Purchase-order status changes are RPC-only.
  insert into public.suppliers (id, name)
  values ('40000000-0000-0000-0000-000000000001', 'DB Test Supplier')
  on conflict (id) do update set name = excluded.name
  returning id into v_supplier;

  insert into public.medicines (id, name, cost_price, selling_price)
  values ('40000000-0000-0000-0000-000000000002', 'DB Test Medicine', 10, 20)
  on conflict (id) do update set name = excluded.name
  returning id into v_medicine;

  insert into public.purchase_orders (id, branch_id, supplier_id, status, total)
  values ('50000000-0000-0000-0000-000000000001', v_branch, v_supplier,
          'draft', 100)
  on conflict (id) do update set status = 'draft', total = 100
  returning id into v_po;

  insert into public.purchase_order_items (id, po_id, medicine_id, quantity_ordered, unit_cost)
  values ('50000000-0000-0000-0000-000000000002', v_po, v_medicine, 10, 10)
  on conflict (id) do update set quantity_ordered = 10, quantity_received = 0,
                                 unit_cost = 10
  returning id into v_po_item;

  perform public.approve_purchase_order(v_po);
  select status::text into v_state from public.purchase_orders where id = v_po;
  insert into db_test_results values
    ('approve_purchase_order_rpc',
     case when v_state = 'ordered' then 'PASS' else 'FAIL' end, v_state);

  begin
    update public.purchase_orders set status = 'cancelled' where id = v_po;
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('purchase_order_direct_status_blocked',
     case when v_state = '42501' then 'PASS' else 'FAIL' end, v_state);

  perform public.receive_purchase_order(v_po, jsonb_build_array(
    jsonb_build_object(
      'po_item_id', v_po_item::text,
      'quantity', 5,
      'batch_no', 'DBT-1',
      'expiry_date', (current_date + 365)::text)));
  select quantity_received::text into v_state
    from public.purchase_order_items where id = v_po_item;
  insert into db_test_results values
    ('receive_purchase_order_updates_quantity',
     case when v_state = '5' then 'PASS' else 'FAIL' end, v_state);

  begin
    update public.purchase_order_items
       set quantity_received = 9 where id = v_po_item;
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('quantity_received_direct_write_blocked',
     case when v_state = '42501' then 'PASS' else 'FAIL' end, v_state);

  -- A separate draft order is used for the cancel path; a partially received
  -- order must stay open so the remaining quantity can still arrive.
  delete from public.purchase_orders
   where id = '50000000-0000-0000-0000-000000000003'::uuid;
  insert into public.purchase_orders (id, branch_id, supplier_id, status, total)
  values ('50000000-0000-0000-0000-000000000003', v_branch, v_supplier,
          'draft', 10);
  perform public.cancel_purchase_order('50000000-0000-0000-0000-000000000003'::uuid);
  select status::text into v_state from public.purchase_orders
   where id = '50000000-0000-0000-0000-000000000003'::uuid;
  insert into db_test_results values
    ('cancel_purchase_order_rpc',
     case when v_state = 'cancelled' then 'PASS' else 'FAIL' end, v_state);

  -- 5. Expense status is approval-controlled.
  insert into public.expenses (id, branch_id, category, amount, created_by)
  values ('60000000-0000-0000-0000-000000000001', v_branch, 'Tests', 25, v_admin)
  on conflict (id) do update set status = 'approved'
  returning id into v_expense;

  begin
    update public.expenses set status = 'pending' where id = v_expense;
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('expense_direct_status_blocked',
     case when v_state = '42501' then 'PASS' else 'FAIL' end, v_state);

  perform public.set_expense_status(v_expense, 'pending');
  perform public.approve_expense(v_expense);
  select status into v_state from public.expenses where id = v_expense;
  insert into db_test_results values
    ('expense_approval_rpc',
     case when v_state = 'approved' then 'PASS' else 'FAIL' end, v_state);

  -- 6. Activity corrections authorize the actor and the approver.
  delete from public.activity_log where entity_id = 'db-test-activity';
  insert into public.activity_log
    (id, actor_id, actor_email, actor_role, action, entity_type, entity_id, branch_id)
  values
    ('70000000-0000-0000-0000-000000000001', v_cashier,
     'cashier@yusra.test', 'cashier', 'UPDATE', 'db_test', 'db-test-activity', v_branch)
  returning id into v_log;

  perform set_config('request.jwt.claim.sub', v_other::text, true);
  begin
    perform public.request_activity_correction(v_log, 'Wrong quantity recorded');
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('activity_correction_other_actor_blocked',
     case when v_state = '42501' then 'PASS' else 'FAIL' end, v_state);

  perform set_config('request.jwt.claim.sub', v_cashier::text, true);
  if not public.request_activity_correction(v_log, 'Wrong quantity recorded') then
    raise exception 'request_activity_correction returned false';
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if not public.approve_activity_correction(v_log) then
    raise exception 'approve_activity_correction returned false';
  end if;
  select approved_by into v_state from public.activity_log where id = v_log;
  insert into db_test_results values
    ('activity_correction_actor_and_super_admin',
     case when v_state = v_admin::text then 'PASS' else 'FAIL' end,
     coalesce(v_state, 'not approved'));

  -- 7. Read helpers and the uniform report date column.
  v_count := (select count(*) from public.customer_stats(v_target));
  v_state := public.shift_expected_cash(
    '00000000-0000-0000-0000-000000000000'::uuid)::text;
  insert into db_test_results values
    ('customer_stats_and_shift_helpers',
     case when v_count > 0 and v_state = '0' then 'PASS' else 'FAIL' end,
     'stats_rows=' || v_count || ',missing_shift=' || v_state);

  select count(*) into v_count
  from information_schema.columns
  where table_schema = 'public'
    and table_name like 'v_report_%'
    and column_name = 'date';
  insert into db_test_results values
    ('all_report_views_have_date',
     case when v_count = 12 then 'PASS' else 'FAIL' end,
     'views_with_date=' || v_count);

  -- ---------------------------------------------------------------------------
  -- 8. Sale returns and voids restore stock and update status correctly.
  --    Admin opens the shift because create_sale() requires the shift owner.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_shift_flow := public.open_shift(v_branch, 100);

  -- Sale 1: 4 units of the medicine received by the PO test above.
  v_sale_flow := public.create_sale(
    v_branch, v_shift_flow, null, null,
    jsonb_build_array(jsonb_build_object('medicine_id', v_medicine::text, 'quantity', 4)),
    jsonb_build_array(jsonb_build_object('method', 'cash', 'amount', 100)),
    0, v_marker);

  select id, batch_id into v_sale_item, v_batch
    from public.sale_items where sale_id = v_sale_flow order by id limit 1;
  select quantity into v_qty_before from public.stock_batches where id = v_batch;

  -- Partial return of one unit: refund is 20.00 and the batch is restocked.
  v_return := public.process_sale_return(
    v_sale_flow,
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', v_sale_item::text, 'quantity', 1, 'restock', true)),
    'DB test partial return', 'cash');

  select refund_amount into v_refund from public.sale_returns where id = v_return;
  select status::text into v_state from public.sales where id = v_sale_flow;
  select quantity into v_qty_after from public.stock_batches where id = v_batch;
  insert into db_test_results values
    ('sale_return_partial_status',
     case when v_state = 'partially_returned' then 'PASS' else 'FAIL' end, v_state);
  insert into db_test_results values
    ('sale_return_partial_refund',
     case when v_refund = 20 then 'PASS' else 'FAIL' end, v_refund::text);
  insert into db_test_results values
    ('sale_return_partial_restores_stock',
     case when v_qty_after = v_qty_before + 1 then 'PASS' else 'FAIL' end,
     v_qty_before::text || '->' || v_qty_after::text);

  -- Returning the remaining three units completes the sale: refund 60.00.
  v_return := public.process_sale_return(
    v_sale_flow,
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', v_sale_item::text, 'quantity', 3, 'restock', true)),
    'DB test full return', 'cash');

  select refund_amount into v_refund from public.sale_returns where id = v_return;
  select status::text into v_state from public.sales where id = v_sale_flow;
  select quantity into v_qty_after from public.stock_batches where id = v_batch;
  insert into db_test_results values
    ('sale_return_full_status',
     case when v_state = 'returned' then 'PASS' else 'FAIL' end, v_state);
  insert into db_test_results values
    ('sale_return_full_refund',
     case when v_refund = 60 then 'PASS' else 'FAIL' end, v_refund::text);
  insert into db_test_results values
    ('sale_return_full_restores_remaining_stock',
     case when v_qty_after = v_qty_before + 4 then 'PASS' else 'FAIL' end,
     v_qty_before::text || '->' || v_qty_after::text);

  -- Void sale: stock returns and a second void is rejected.
  v_sale_void := public.create_sale(
    v_branch, v_shift_flow, null, null,
    jsonb_build_array(jsonb_build_object('medicine_id', v_medicine::text, 'quantity', 2)),
    jsonb_build_array(jsonb_build_object('method', 'cash', 'amount', 40)),
    0, v_marker);

  select batch_id into v_batch from public.sale_items where sale_id = v_sale_void limit 1;
  select quantity into v_qty_before from public.stock_batches where id = v_batch;
  perform public.void_sale(v_sale_void, 'DB test void');
  select status::text into v_state from public.sales where id = v_sale_void;
  select quantity into v_qty_after from public.stock_batches where id = v_batch;
  insert into db_test_results values
    ('void_sale_status',
     case when v_state = 'voided' then 'PASS' else 'FAIL' end, v_state);
  insert into db_test_results values
    ('void_sale_restores_stock',
     case when v_qty_after = v_qty_before + 2 then 'PASS' else 'FAIL' end,
     v_qty_before::text || '->' || v_qty_after::text);

  begin
    perform public.void_sale(v_sale_void, 'DB test double void');
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('void_sale_double_rejected',
     case when v_state <> 'NO_ERROR' then 'PASS' else 'FAIL' end, v_state);

  -- A cashier can view sales but must not be able to return or void them.
  v_sale_guard := public.create_sale(
    v_branch, v_shift_flow, null, null,
    jsonb_build_array(jsonb_build_object('medicine_id', v_medicine::text, 'quantity', 1)),
    jsonb_build_array(jsonb_build_object('method', 'cash', 'amount', 20)),
    0, v_marker);
  select id into v_sale_item from public.sale_items where sale_id = v_sale_guard limit 1;

  perform set_config('request.jwt.claim.sub', v_cashier::text, true);
  begin
    perform public.process_sale_return(
      v_sale_guard,
      jsonb_build_array(jsonb_build_object('sale_item_id', v_sale_item::text, 'quantity', 1)),
      'DB test cashier return', 'cash');
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('cashier_cannot_process_sale_return',
     case when v_state <> 'NO_ERROR' then 'PASS' else 'FAIL' end, v_state);

  begin
    perform public.void_sale(v_sale_guard, 'DB test cashier void');
    v_state := 'NO_ERROR';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  insert into db_test_results values
    ('cashier_cannot_void_sale',
     case when v_state <> 'NO_ERROR' then 'PASS' else 'FAIL' end, v_state);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  -- close_shift() expected cash = opening + cash sales - change - cash refunds.
  select s.opening_cash
       + coalesce((select sum(sp.amount)
                     from public.sale_payments sp
                    where sp.sale_id in (
                      select id from public.sales
                       where shift_id = s.id and status <> 'voided')
                      and sp.method = 'cash'), 0)
       - coalesce((select sum(change_due)
                     from public.sales
                    where shift_id = s.id and status <> 'voided'), 0)
       - coalesce((select sum(r.refund_amount)
                     from public.sale_returns r
                     join public.sales rs on rs.id = r.sale_id
                    where rs.shift_id = s.id and r.refund_method = 'cash'), 0)
    into v_expected_cash
    from public.shifts s
   where s.id = v_shift_flow;

  v_detail := public.close_shift(v_shift_flow, v_expected_cash, 'DB test close')::text;
  insert into db_test_results values
    ('close_shift_expected_cash_formula',
     case when (v_detail::jsonb ->> 'expected_cash')::numeric = v_expected_cash
          then 'PASS' else 'FAIL' end,
     'expected=' || v_expected_cash::text || ',result=' || coalesce(v_detail, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 9. PostgREST grant checks (0021_grants.sql). These assert table-level
--    privileges only: RLS remains the gatekeeper for which rows are visible.
--    Every check is inserted into db_test_results, so a missing grant is
--    reported by the tabular result below AND by the failure guard at the end.
-- ---------------------------------------------------------------------------
do $$
declare
  v_log oid := to_regclass('public.activity_log');
begin
  insert into db_test_results values
    ('grant_anon_schema_usage',
     case when has_schema_privilege('anon', 'public', 'USAGE')
          then 'PASS' else 'FAIL' end,
     'anon needs schema USAGE for PostgREST'),
    ('grant_authenticated_schema_usage',
     case when has_schema_privilege('authenticated', 'public', 'USAGE')
          then 'PASS' else 'FAIL' end,
     'authenticated needs schema USAGE for PostgREST'),
    ('grant_authenticated_core_table_access',
     case when (select bool_and(
                      has_table_privilege('authenticated', c.oid, 'SELECT')
                  and has_table_privilege('authenticated', c.oid, 'INSERT')
                  and has_table_privilege('authenticated', c.oid, 'UPDATE')
                  and has_table_privilege('authenticated', c.oid, 'DELETE'))
                from pg_class c
                join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public'
                  and c.relkind in ('r', 'p', 'v', 'f')
                  and c.relname <> 'activity_log')
          then 'PASS' else 'FAIL' end,
     'CRUD on every public table except activity_log'),
    ('grant_authenticated_activity_log_select',
     case when has_table_privilege('authenticated', v_log, 'SELECT')
          then 'PASS' else 'FAIL' end,
     'authenticated can read the activity log'),
    ('grant_authenticated_activity_log_no_update_delete',
     case when not has_table_privilege('authenticated', v_log, 'UPDATE')
               and not has_table_privilege('authenticated', v_log, 'DELETE')
          then 'PASS' else 'FAIL' end,
     'activity_log is append-only for clients'),
    ('grant_anon_activity_log_no_access',
     case when not (
                   has_table_privilege('anon', v_log, 'SELECT')
                or has_table_privilege('anon', v_log, 'INSERT')
                or has_table_privilege('anon', v_log, 'UPDATE')
                or has_table_privilege('anon', v_log, 'DELETE')
                or has_table_privilege('anon', v_log, 'TRUNCATE')
                or has_table_privilege('anon', v_log, 'REFERENCES')
                or has_table_privilege('anon', v_log, 'TRIGGER')
              ) then 'PASS' else 'FAIL' end,
     'anon has no activity_log privileges'),
    ('grant_authenticated_sequence_access',
     case when exists (
                   select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relkind = 'S'
                 )
                 and not exists (
                   select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relkind = 'S'
                     and not (has_sequence_privilege('authenticated', c.oid, 'USAGE')
                          and has_sequence_privilege('authenticated', c.oid, 'SELECT'))
                 )
          then 'PASS' else 'FAIL' end,
     'USAGE and SELECT on every public sequence'),
    ('grant_default_privileges_tables',
     case when exists (
       select 1 from pg_default_acl d
       join pg_namespace n on n.oid = d.defaclnamespace
       where n.nspname = 'public'
         and d.defaclobjtype = 'r'
         and d.defaclrole = (select c.relowner from pg_class c where c.oid = to_regclass('public.branches'))
         and (select array_agg(x.privilege_type)
              from aclexplode(d.defaclacl) x
              join pg_roles r on r.oid = x.grantee
              where r.rolname = 'authenticated')
             @> array['SELECT','INSERT','UPDATE','DELETE']::text[]
     ) then 'PASS' else 'FAIL' end,
     'future public tables inherit CRUD for authenticated'),
    ('grant_default_privileges_sequences',
     case when exists (
       select 1 from pg_default_acl d
       join pg_namespace n on n.oid = d.defaclnamespace
       where n.nspname = 'public'
         and d.defaclobjtype = 'S'
         and d.defaclrole = (select c.relowner from pg_class c where c.oid = to_regclass('public.branches'))
         and (select array_agg(x.privilege_type)
              from aclexplode(d.defaclacl) x
              join pg_roles r on r.oid = x.grantee
              where r.rolname = 'authenticated')
             @> array['SELECT','USAGE']::text[]
     ) then 'PASS' else 'FAIL' end,
     'future public sequences inherit USAGE/SELECT for authenticated');
end $$;

select test, status, detail from db_test_results order by test;

-- Compact grant-only lines, e.g. "PASS grant authenticated core table access".
-- The tabular result above and the failure guard below are unchanged.
select case when status = 'FAIL'
            then 'FAIL ' || replace(test, '_', ' ') || ': ' || detail
            else 'PASS ' || replace(test, '_', ' ') end as grant_check
from db_test_results
where test like 'grant_%'
order by test;

do $$
declare
  v_fails int;
begin
  select count(*) into v_fails from db_test_results where status = 'FAIL';
  if v_fails > 0 then
    raise exception 'db_test.sql: % check(s) failed', v_fails;
  end if;
end $$;
