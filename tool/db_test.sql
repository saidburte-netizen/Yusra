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
end $$;

select test, status, detail from db_test_results order by test;

do $$
declare
  v_fails int;
begin
  select count(*) into v_fails from db_test_results where status = 'FAIL';
  if v_fails > 0 then
    raise exception 'db_test.sql: % check(s) failed', v_fails;
  end if;
end $$;
