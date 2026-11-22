-- 0023 — PR #19 review fixes.
--
-- Idempotent on PostgreSQL 16. Fixes:
--   1. branch/role guards on every view built from branches or unguarded tables;
--   2. NULL cost in the 7-argument add_stock_batch overload;
--   3. friendly, row-numbered validation errors in bulk RPCs;
--   4. branch-scoped negative coverage is added to db_test.sql and e2e-api.

-- ---------------------------------------------------------------------------
-- 1. Views: every branch-exposed view now checks branch AND role explicitly.
--    security_invoker RLS alone is not enough for views that manufacture rows
--    from `branches cross join ...` or that aggregate unguarded parent tables.
-- ---------------------------------------------------------------------------
create or replace view v_stock_summary with (security_invoker = true) as
select
  b.id as branch_id,
  m.id as medicine_id,
  m.name,
  m.generic_name,
  m.sku,
  m.barcode,
  m.category_id,
  m.unit,
  m.reorder_level,
  m.selling_price,
  m.cost_price,
  m.is_active,
  coalesce(sum(sb.quantity) filter (where sb.expiry_date > current_date), 0)::int as available_qty,
  coalesce(sum(sb.quantity) filter (where sb.expiry_date <= current_date), 0)::int as expired_qty,
  min(sb.expiry_date) filter (where sb.quantity > 0 and sb.expiry_date > current_date) as nearest_expiry
from branches b
cross join medicines m
left join stock_batches sb
  on sb.branch_id = b.id and sb.medicine_id = m.id and sb.is_active
where b.is_active
  and can_access_branch(b.id)
  and has_role('super_admin', 'admin', 'pharmacist', 'cashier', 'store_keeper', 'accountant')
group by b.id, m.id;

create or replace view v_low_stock with (security_invoker = true) as
select * from v_stock_summary
where is_active
  and available_qty <= reorder_level
  and can_access_branch(branch_id)
  and has_role('super_admin', 'admin', 'pharmacist', 'cashier', 'store_keeper', 'accountant');

create or replace view v_expiring_batches with (security_invoker = true) as
select
  sb.id as batch_id,
  sb.branch_id,
  sb.medicine_id,
  m.name,
  sb.batch_no,
  sb.expiry_date,
  sb.quantity,
  (sb.expiry_date - current_date) as days_left,
  (sb.expiry_date <= current_date) as is_expired
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.quantity > 0 and sb.is_active
  and sb.expiry_date <= current_date + coalesce((select (value #>> '{}')::int from app_settings where key = 'expiry_alert_days'), 90)
  and can_access_branch(sb.branch_id)
  and has_role('super_admin', 'admin', 'pharmacist', 'cashier', 'store_keeper', 'accountant');

create or replace view v_daily_sales with (security_invoker = true) as
select * from (
  select
    branch_id,
    (created_at at time zone 'Africa/Addis_Ababa')::date as sale_date,
    count(*)::int as invoices,
    sum(subtotal) as subtotal,
    sum(discount) as discount,
    sum(tax) as tax,
    sum(total) as total
  from sales
  where status <> 'voided'
  group by branch_id, (created_at at time zone 'Africa/Addis_Ababa')::date
) s
where can_access_branch(s.branch_id)
  and has_role('super_admin', 'admin', 'accountant');

create or replace view public.v_reorder_suggestions with (security_invoker = true) as
select * from (
  with stock as (
    select sb.branch_id,
           sb.medicine_id,
           coalesce(sum(sb.quantity) filter (where sb.expiry_date > current_date), 0)::int as on_hand,
           coalesce(sum(sb.quantity) filter (where sb.expiry_date > current_date + 30), 0)::int as available_qty,
           coalesce(sum(sb.quantity) filter (where sb.expiry_date > current_date
                                              and sb.expiry_date <= current_date + 30), 0)::int as expiring_qty
      from public.stock_batches sb
     where sb.is_active and sb.quantity > 0
     group by sb.branch_id, sb.medicine_id
  ),
  last_cost as (
    select distinct on (po.branch_id, poi.medicine_id)
           po.branch_id, poi.medicine_id, poi.unit_cost
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.po_id
     where poi.quantity_received > 0
     order by po.branch_id, poi.medicine_id, po.order_date desc, po.created_at desc, poi.id desc
  )
  select
    b.id as branch_id,
    m.id as medicine_id,
    m.name,
    m.sku,
    m.unit,
    coalesce(s.on_hand, 0)::int as on_hand,
    coalesce(s.available_qty, 0)::int as available_qty,
    coalesce(s.expiring_qty, 0)::int as expiring_qty,
    m.reorder_level,
    coalesce(m.target_level, m.reorder_level * 2)::int as target_level,
    greatest(coalesce(m.target_level, m.reorder_level * 2) - coalesce(s.available_qty, 0), 1)::int
      as suggested_order_qty,
    m.preferred_supplier_id,
    sup.name as preferred_supplier_name,
    coalesce(lc.unit_cost, 0)::numeric(14,2) as last_purchase_cost,
    case
      when coalesce(s.expiring_qty, 0) > 0 and coalesce(s.available_qty, 0) <= m.reorder_level
        then 'Below reorder level; stock expiring within 30 days'
      when coalesce(s.expiring_qty, 0) > 0
        then 'Stock expiring within 30 days'
      else 'Below reorder level'
    end as reason
  from public.branches b
  cross join public.medicines m
  left join stock s on s.branch_id = b.id and s.medicine_id = m.id
  left join public.suppliers sup on sup.id = m.preferred_supplier_id
  left join last_cost lc on lc.branch_id = b.id and lc.medicine_id = m.id
  where b.is_active and m.is_active
    and (coalesce(s.available_qty, 0) <= m.reorder_level or coalesce(s.expiring_qty, 0) > 0)
) r
where can_access_branch(r.branch_id)
  and has_role('super_admin', 'admin', 'pharmacist', 'store_keeper');

create or replace view v_report_sales_by_day with (security_invoker = true) as
select * from (
  select
    (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
    count(*)::int as invoices,
    coalesce(sum(s.subtotal), 0) as gross,
    coalesce(sum(s.discount), 0) as discounts,
    coalesce(sum(s.tax), 0) as vat,
    coalesce(sum(s.total), 0) as net,
    s.branch_id
  from sales s
  where s.status <> 'voided'
  group by 1, s.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_sales_by_cashier with (security_invoker = true) as
select * from (
  select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
         coalesce(nullif(p.full_name, ''), s.cashier_id::text) as cashier,
         count(*)::int as invoices,
         coalesce(sum(s.total), 0) as total,
         s.branch_id
  from sales s
  left join profiles p on p.id = s.cashier_id
  where s.status <> 'voided'
  group by 1, 2, s.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_sales_payment with (security_invoker = true) as
select * from (
  select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
         sp.method::text as payment_method,
         count(distinct sp.sale_id)::int as invoices,
         coalesce(sum(sp.amount), 0) as total,
         s.branch_id
  from sale_payments sp
  join sales s on s.id = sp.sale_id
  where s.status <> 'voided'
  group by 1, 2, s.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_sales_by_medicine with (security_invoker = true) as
select * from (
  select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
         si.medicine_name as medicine,
         sum(si.quantity - si.returned_qty)::int as qty,
         coalesce(sum(si.line_total - si.discount_share), 0) as revenue,
         coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
         coalesce(sum(si.line_total - si.discount_share - si.cost_price * (si.quantity - si.returned_qty)), 0) as profit,
         s.branch_id
  from sale_items si
  join sales s on s.id = si.sale_id
  where s.status <> 'voided'
  group by 1, 2, s.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_profit with (security_invoker = true) as
select * from (
  with daily_revenue as (
    select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
           coalesce(sum(s.total), 0) as revenue,
           s.branch_id
    from sales s
    where s.status <> 'voided'
    group by 1, s.branch_id
  ), daily_cost as (
    select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
           coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
           s.branch_id
    from sale_items si
    join sales s on s.id = si.sale_id
    where s.status <> 'voided'
    group by 1, s.branch_id
  )
  select
    coalesce(r.date, c.date) as date,
    coalesce(r.revenue, 0) as revenue,
    coalesce(c.cost, 0) as cost,
    coalesce(r.revenue, 0) - coalesce(c.cost, 0) as profit,
    case when coalesce(r.revenue, 0) = 0 then 0
         else round(((coalesce(r.revenue, 0) - coalesce(c.cost, 0))
           / r.revenue * 100)::numeric, 2) end as margin,
    coalesce(r.branch_id, c.branch_id) as branch_id
  from daily_revenue r
  full join daily_cost c on c.date = r.date and c.branch_id = r.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_stock_valuation with (security_invoker = true) as
select * from (
  select current_date as date,
         m.name as medicine,
         sum(sb.quantity)::int as qty,
         case when sum(sb.quantity) = 0 then 0
              else round(sum(sb.quantity::numeric * sb.cost_price) / sum(sb.quantity)::numeric, 2)
         end as unit_cost,
         coalesce(sum(sb.quantity::numeric * sb.cost_price), 0) as value,
         sb.branch_id
  from stock_batches sb
  join medicines m on m.id = sb.medicine_id
  where sb.is_active and sb.quantity > 0
  group by m.id, m.name, sb.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_expiry_losses with (security_invoker = true) as
select * from (
  select sb.expiry_date as date,
         sb.expiry_date as expiry,
         m.name as medicine,
         sb.batch_no as batch,
         sb.quantity as qty,
         coalesce(sb.quantity::numeric * sb.cost_price, 0) as value,
         sb.branch_id
  from stock_batches sb
  join medicines m on m.id = sb.medicine_id
  where sb.is_active and sb.quantity > 0 and sb.expiry_date <= current_date
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_purchases_supplier with (security_invoker = true) as
select * from (
  select (min(po.order_date)) as date,
         s.name as supplier,
         count(*)::int as orders,
         coalesce(sum(po.total), 0) as total,
         po.branch_id
  from purchase_orders po
  join suppliers s on s.id = po.supplier_id
  where po.status not in ('draft', 'cancelled')
  group by s.id, s.name, po.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_expenses with (security_invoker = true) as
select * from (
  select expense_date as date,
         category,
         coalesce(sum(amount), 0) as amount,
         branch_id
  from expenses
  group by expense_date, category, branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_net_profit with (security_invoker = true) as
select * from (
  with revenue as (
    select to_char(s.created_at at time zone 'Africa/Addis_Ababa', 'YYYY-MM') as period,
           coalesce(sum(s.total), 0) as revenue,
           s.branch_id
    from sales s
    where s.status <> 'voided'
    group by 1, s.branch_id
  ), costs as (
    select to_char(e.expense_date::timestamp, 'YYYY-MM') as period,
           coalesce(sum(e.amount), 0) as expenses,
           branch_id
    from expenses e
    group by 1, branch_id
  )
  select (coalesce(r.period, c.period) || '-01')::date as date,
         coalesce(r.period, c.period) as period,
         coalesce(r.revenue, 0) as revenue,
         coalesce(c.expenses, 0) as expenses,
         coalesce(r.revenue, 0) - coalesce(c.expenses, 0) as net,
         coalesce(r.branch_id, c.branch_id) as branch_id
  from revenue r
  full join costs c on c.period = r.period and c.branch_id = r.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_shift_variance with (security_invoker = true) as
select * from (
  select (sh.opened_at at time zone 'Africa/Addis_Ababa')::date as date,
         coalesce(nullif(p.full_name, ''), sh.cashier_id::text) as cashier,
         to_char(sh.opened_at at time zone 'Africa/Addis_Ababa', 'YYYY-MM-DD HH24:MI') as shift,
         coalesce(sh.expected_cash, 0) as expected,
         coalesce(sh.closing_cash, 0) as actual,
         coalesce(sh.closing_cash, 0) - coalesce(sh.expected_cash, 0) as variance,
         sh.branch_id
  from shifts sh
  left join profiles p on p.id = sh.cashier_id
  where sh.status = 'closed'
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

create or replace view v_report_controlled_register with (security_invoker = true) as
select * from (
  select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
         si.medicine_name as medicine,
         sum(si.quantity - si.returned_qty)::int as qty,
         coalesce(rx.prescriber_name, '') as prescriber,
         coalesce(rx.patient_name, '') as patient,
         s.branch_id
  from sale_items si
  join sales s on s.id = si.sale_id
  join medicines m on m.id = si.medicine_id
  left join prescriptions rx on rx.id = s.prescription_id
  where s.status <> 'voided' and m.is_controlled
  group by 1, 2, 4, 5, s.branch_id
) r
where can_access_branch(r.branch_id) and has_role('super_admin', 'admin', 'accountant');

-- ---------------------------------------------------------------------------
-- 1b. activity_log was branch-scoped but readable by every authenticated user.
--     Restrict reads to rows in branches the caller can access.
-- ---------------------------------------------------------------------------
drop policy if exists rls_activity_read on public.activity_log;
create policy rls_activity_read on public.activity_log for select to authenticated
using (can_access_branch(branch_id));

-- ---------------------------------------------------------------------------
-- 2. NULL cost in the 7-argument overload must behave as zero, not fail.
-- ---------------------------------------------------------------------------
create or replace function public.add_stock_batch(
  p_branch uuid,
  p_medicine uuid,
  p_batch_no text,
  p_expiry date,
  p_quantity int,
  p_cost numeric default 0,
  p_supplier uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  return public.add_stock_batch(
    p_branch, p_medicine, p_batch_no, p_expiry, p_quantity,
    coalesce(p_cost, 0), p_supplier, 'opening');
end $$;

-- ---------------------------------------------------------------------------
-- 3a. add_opening_stock with row-numbered, friendly validation.
-- ---------------------------------------------------------------------------
create or replace function public.add_opening_stock(p_branch uuid, p_rows jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_row jsonb;
  v_index int;
  v_rows jsonb := '[]'::jsonb;
  v_medicine uuid;
  v_batch text;
  v_expiry date;
  v_qty int;
  v_cost numeric;
  v_seen text[] := array[]::text[];
  v_id uuid;
  v_prefix text := 'OPEN-' || to_char(current_date, 'YYYYMMDD') || '-';
  v_seq int;
  v_saved int := 0;
begin
  if not has_role('super_admin', 'admin', 'pharmacist', 'store_keeper') then
    raise exception 'You are not allowed to add stock' using errcode = '42501';
  end if;
  if not can_access_branch(p_branch) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Rows must be a JSON array' using errcode = '22023';
  end if;

  -- Validation pass: every bad value raises 22023 with a row number and field.
  for v_row, v_index in
    select value, ordinality from jsonb_array_elements(p_rows) with ordinality
  loop
    if v_row is null or jsonb_typeof(v_row) <> 'object' then
      raise exception 'Row %: expected an object', v_index using errcode = '22023';
    end if;

    if not (v_row ? 'medicine_id')
       or nullif(btrim(coalesce(v_row ->> 'medicine_id', '')), '') is null then
      raise exception 'Row %: field medicine_id is required', v_index using errcode = '22023';
    end if;
    begin
      v_medicine := nullif(btrim(v_row ->> 'medicine_id'), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Row %: field medicine_id must be a UUID', v_index using errcode = '22023';
    end;
    if not exists (select 1 from public.medicines where id = v_medicine and is_active) then
      raise exception 'Row %: medicine_id not found or inactive', v_index using errcode = '22023';
    end if;

    if not (v_row ? 'quantity')
       or nullif(btrim(coalesce(v_row ->> 'quantity', '')), '') is null then
      raise exception 'Row %: field quantity is required', v_index using errcode = '22023';
    end if;
    begin
      v_qty := (v_row ->> 'quantity')::int;
    exception when invalid_text_representation then
      raise exception 'Row %: field quantity must be an integer', v_index using errcode = '22023';
    end;
    if v_qty <= 0 then
      raise exception 'Row %: field quantity must be greater than zero', v_index using errcode = '22023';
    end if;

    if not (v_row ? 'expiry_date')
       or nullif(btrim(coalesce(v_row ->> 'expiry_date', '')), '') is null then
      raise exception 'Row %: field expiry_date is required', v_index using errcode = '22023';
    end if;
    begin
      v_expiry := nullif(btrim(v_row ->> 'expiry_date'), '')::date;
    exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Row %: field expiry_date must be a valid date', v_index using errcode = '22023';
    end;
    if v_expiry <= current_date then
      raise exception 'Row %: field expiry_date must be in the future', v_index using errcode = '22023';
    end if;

    begin
      v_cost := coalesce(nullif(btrim(coalesce(v_row ->> 'unit_cost', '')), '')::numeric, 0);
    exception when invalid_text_representation then
      raise exception 'Row %: field unit_cost must be a number', v_index using errcode = '22023';
    end;
    if v_cost < 0 then
      raise exception 'Row %: field unit_cost must not be negative', v_index using errcode = '22023';
    end if;

    v_batch := nullif(btrim(coalesce(v_row ->> 'batch_no', '')), '');
    if v_batch is not null then
      if v_batch = any(v_seen) then
        raise exception 'Row %: duplicate batch_no % in this request', v_index, v_batch using errcode = '22023';
      end if;
      v_seen := v_seen || v_batch;
    end if;

    v_rows := v_rows || jsonb_build_object(
      'medicine_id', v_medicine::text,
      'quantity', v_qty,
      'expiry_date', v_expiry::text,
      'batch_no', v_batch,
      'unit_cost', v_cost);
  end loop;

  -- Write pass: normalized values are safe casts.
  for v_row in select value from jsonb_array_elements(v_rows) loop
    v_medicine := (v_row ->> 'medicine_id')::uuid;
    v_qty := (v_row ->> 'quantity')::int;
    v_expiry := (v_row ->> 'expiry_date')::date;
    v_cost := (v_row ->> 'unit_cost')::numeric;
    v_batch := nullif(btrim(coalesce(v_row ->> 'batch_no', '')), '');

    if v_batch is null then
      v_seq := 1;
      loop
        if v_seq > 999 then
          raise exception 'Unable to generate a unique batch number' using errcode = '22023';
        end if;
        v_batch := v_prefix || lpad(v_seq::text, 3, '0');
        begin
          insert into public.stock_batches
            (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price)
          values
            (p_branch, v_medicine, v_batch, v_expiry, v_qty, v_qty, v_cost)
          returning id into v_id;
          exit;
        exception when unique_violation then
          v_seq := v_seq + 1;
        end;
      end loop;
    else
      insert into public.stock_batches
        (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price)
      values
        (p_branch, v_medicine, v_batch, v_expiry, v_qty, v_qty, v_cost)
      on conflict (branch_id, medicine_id, batch_no) do update
         set quantity = public.stock_batches.quantity + excluded.quantity,
             initial_quantity = public.stock_batches.initial_quantity + excluded.quantity,
             updated_at = now()
      returning id into v_id;
    end if;

    insert into public.stock_movements
      (branch_id, medicine_id, batch_id, movement_type, quantity_change, reason)
    values
      (p_branch, v_medicine, v_id, 'opening', v_qty, 'Opening stock registered');

    v_saved := v_saved + 1;
  end loop;

  return v_saved;
end $$;

-- ---------------------------------------------------------------------------
-- 3b. create_draft_purchase_orders with row-numbered, friendly validation.
-- ---------------------------------------------------------------------------
create or replace function public.create_draft_purchase_orders(
  p_branch uuid,
  p_lines jsonb
) returns uuid[]
language plpgsql security definer set search_path = public as $$
declare
  v_line jsonb;
  v_index int;
  v_lines jsonb := '[]'::jsonb;
  v_supplier uuid;
  v_medicine uuid;
  v_qty int;
  v_cost numeric;
  v_po_map jsonb := '{}'::jsonb;
  v_po uuid;
  v_ids uuid[] := array[]::uuid[];
begin
  if not has_role('super_admin', 'admin', 'pharmacist', 'store_keeper') then
    raise exception 'You are not allowed to create purchase orders' using errcode = '42501';
  end if;
  if not can_access_branch(p_branch) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Lines must be a JSON array' using errcode = '22023';
  end if;

  for v_line, v_index in
    select value, ordinality from jsonb_array_elements(p_lines) with ordinality
  loop
    if v_line is null or jsonb_typeof(v_line) <> 'object' then
      raise exception 'Row %: expected an object', v_index using errcode = '22023';
    end if;

    if not (v_line ? 'supplier_id')
       or nullif(btrim(coalesce(v_line ->> 'supplier_id', '')), '') is null then
      raise exception 'Row %: field supplier_id is required (Choose supplier)', v_index using errcode = '22023';
    end if;
    begin
      v_supplier := nullif(btrim(v_line ->> 'supplier_id'), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Row %: field supplier_id must be a UUID', v_index using errcode = '22023';
    end;
    if not exists (select 1 from public.suppliers where id = v_supplier and is_active) then
      raise exception 'Row %: supplier_id not found or inactive', v_index using errcode = '22023';
    end if;

    if not (v_line ? 'medicine_id')
       or nullif(btrim(coalesce(v_line ->> 'medicine_id', '')), '') is null then
      raise exception 'Row %: field medicine_id is required', v_index using errcode = '22023';
    end if;
    begin
      v_medicine := nullif(btrim(v_line ->> 'medicine_id'), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Row %: field medicine_id must be a UUID', v_index using errcode = '22023';
    end;
    if not exists (select 1 from public.medicines where id = v_medicine and is_active) then
      raise exception 'Row %: medicine_id not found or inactive', v_index using errcode = '22023';
    end if;

    if not (v_line ? 'quantity')
       or nullif(btrim(coalesce(v_line ->> 'quantity', '')), '') is null then
      raise exception 'Row %: field quantity is required', v_index using errcode = '22023';
    end if;
    begin
      v_qty := (v_line ->> 'quantity')::int;
    exception when invalid_text_representation then
      raise exception 'Row %: field quantity must be an integer', v_index using errcode = '22023';
    end;
    if v_qty <= 0 then
      raise exception 'Row %: field quantity must be greater than zero', v_index using errcode = '22023';
    end if;

    if not (v_line ? 'unit_cost')
       or nullif(btrim(coalesce(v_line ->> 'unit_cost', '')), '') is null then
      raise exception 'Row %: field unit_cost is required', v_index using errcode = '22023';
    end if;
    begin
      v_cost := (v_line ->> 'unit_cost')::numeric;
    exception when invalid_text_representation then
      raise exception 'Row %: field unit_cost must be a number', v_index using errcode = '22023';
    end;
    if v_cost < 0 then
      raise exception 'Row %: field unit_cost must not be negative', v_index using errcode = '22023';
    end if;

    v_lines := v_lines || jsonb_build_object(
      'supplier_id', v_supplier::text,
      'medicine_id', v_medicine::text,
      'quantity', v_qty,
      'unit_cost', v_cost);
  end loop;

  begin
    perform set_config('app.via_rpc', '1', true);
    for v_line in select value from jsonb_array_elements(v_lines) loop
      v_supplier := (v_line ->> 'supplier_id')::uuid;
      if not (v_po_map ? v_supplier::text) then
        insert into public.purchase_orders
          (branch_id, supplier_id, po_no, status, order_date, notes)
        values
          (p_branch, v_supplier, public.next_doc_no('PO', p_branch), 'draft',
           current_date, 'Created from reorder suggestions')
        returning id into v_po;
        v_po_map := v_po_map || jsonb_build_object(v_supplier::text, v_po::text);
        v_ids := v_ids || v_po;
      end if;
      v_po := (v_po_map ->> v_supplier::text)::uuid;

      insert into public.purchase_order_items
        (po_id, medicine_id, quantity_ordered, unit_cost)
      values
        (v_po, (v_line ->> 'medicine_id')::uuid,
         (v_line ->> 'quantity')::int, (v_line ->> 'unit_cost')::numeric)
      on conflict (po_id, medicine_id) do update
         set quantity_ordered = public.purchase_order_items.quantity_ordered + excluded.quantity_ordered,
             unit_cost = excluded.unit_cost;
    end loop;
    perform set_config('app.via_rpc', '', true);
  exception when others then
    perform set_config('app.via_rpc', '', true);
    raise;
  end;

  return v_ids;
end $$;

-- Grants are unchanged; reasserted so a fresh owner run is complete.
revoke all on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) from public, anon;
grant execute on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) to authenticated;
revoke all on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid, text) from public, anon;
grant execute on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid, text) to authenticated;
revoke all on function public.add_opening_stock(uuid, jsonb) from public, anon;
grant execute on function public.add_opening_stock(uuid, jsonb) to authenticated;
revoke all on function public.create_draft_purchase_orders(uuid, jsonb) from public, anon;
grant execute on function public.create_draft_purchase_orders(uuid, jsonb) to authenticated;
