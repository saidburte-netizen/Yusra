-- 0022 — Opening stock, auto-generated batches, reorder suggestions and draft POs.
--
-- Idempotent: every statement is safe to re-run (PostgreSQL 16).
-- The RPC JSON contracts used by the Flutter app are fixed:
--   add_opening_stock(uuid, jsonb) returns int
--   create_draft_purchase_orders(uuid, jsonb) returns uuid[]
--   add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) keeps its 7 args
--   add_stock_batch(uuid, uuid, text, date, int, numeric, uuid, text) is new

-- ---------------------------------------------------------------------------
-- 1. Medicine columns that drive reorder suggestions.
-- ---------------------------------------------------------------------------
alter table public.medicines
  add column if not exists preferred_supplier_id uuid
    references public.suppliers(id) on delete set null;

alter table public.medicines
  add column if not exists target_level int;

-- Only fill medicines that have never had a target; a blank target is shown
-- as reorder_level * 2 in the app and in the view.
update public.medicines
   set target_level = reorder_level * 2
 where target_level is null;

-- ---------------------------------------------------------------------------
-- 2. New 8-argument add_stock_batch. The 8th argument is REQUIRED and there
--    are no defaults on this overload, so calls with 7 args keep resolving to
--    the original signature. All validation is done before any write.
-- ---------------------------------------------------------------------------
create or replace function public.add_stock_batch(
  p_branch uuid,
  p_medicine uuid,
  p_batch_no text,
  p_expiry date,
  p_quantity int,
  p_cost numeric,
  p_supplier uuid,
  p_source text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_batch text := nullif(btrim(coalesce(p_batch_no, '')), '');
  v_auto boolean := v_batch is null;
  v_prefix text;
  v_seq int := 1;
  v_movement movement_type := 'opening';
begin
  if not has_role('super_admin', 'admin', 'pharmacist', 'store_keeper') then
    raise exception 'You are not allowed to add stock' using errcode = '42501';
  end if;
  if not can_access_branch(p_branch) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;
  if p_source is null or btrim(p_source) not in ('opening', 'purchase', 'other') then
    raise exception 'Invalid stock source' using errcode = '22023';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero' using errcode = '22023';
  end if;
  if p_expiry is null or p_expiry <= current_date then
    raise exception 'Expiry date must be in the future' using errcode = '22023';
  end if;
  if p_cost is null or p_cost < 0 then
    raise exception 'Cost must not be negative' using errcode = '22023';
  end if;
  if not exists (select 1 from public.medicines where id = p_medicine and is_active) then
    raise exception 'Medicine not found or inactive' using errcode = '22023';
  end if;
  if p_supplier is not null
     and not exists (select 1 from public.suppliers where id = p_supplier) then
    raise exception 'Supplier not found' using errcode = '22023';
  end if;

  if btrim(p_source) = 'purchase' and p_supplier is not null then
    v_movement := 'purchase';
  end if;

  if not v_auto then
    -- Explicit batch numbers keep the historical accumulation behaviour.
    insert into public.stock_batches
      (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price, supplier_id)
    values
      (p_branch, p_medicine, v_batch, p_expiry, p_quantity, p_quantity, p_cost, p_supplier)
    on conflict (branch_id, medicine_id, batch_no) do update
       set quantity = public.stock_batches.quantity + excluded.quantity,
           initial_quantity = public.stock_batches.initial_quantity + excluded.quantity,
           updated_at = now()
    returning id into v_id;
  else
    -- Blank / null batch: OPEN-YYYYMMDD-NNN, counting up for this medicine+branch.
    v_prefix := 'OPEN-' || to_char(current_date, 'YYYYMMDD') || '-';
    loop
      if v_seq > 999 then
        raise exception 'Unable to generate a unique batch number' using errcode = '22023';
      end if;
      v_batch := v_prefix || lpad(v_seq::text, 3, '0');
      begin
        insert into public.stock_batches
          (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price, supplier_id)
        values
          (p_branch, p_medicine, v_batch, p_expiry, p_quantity, p_quantity, p_cost, p_supplier)
        returning id into v_id;
        exit;
      exception when unique_violation then
        -- Another row took this suffix; try the next one.
        v_seq := v_seq + 1;
      end;
    end loop;
  end if;

  insert into public.stock_movements
    (branch_id, medicine_id, batch_id, movement_type, quantity_change, reason)
  values
    (p_branch, p_medicine, v_id, v_movement, p_quantity, 'Stock added manually');

  return v_id;
end $$;

-- The original 7-argument signature is unchanged; blank batches now generate
-- OPEN-YYYYMMDD-NNN and the movement type is always opening.
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
    p_branch, p_medicine, p_batch_no, p_expiry, p_quantity, p_cost, p_supplier, 'opening');
end $$;

-- ---------------------------------------------------------------------------
-- 3. add_opening_stock — atomic bulk opening-stock registration.
--    Every row is validated before the first write; any bad row aborts the
--    whole call. Rows without a batch number get an auto-generated one.
-- ---------------------------------------------------------------------------
create or replace function public.add_opening_stock(p_branch uuid, p_rows jsonb)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_row jsonb;
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

  -- Validation pass: normalize each row, reject duplicates and bad values.
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_medicine := nullif(btrim(coalesce(v_row ->> 'medicine_id', '')), '')::uuid;
    if v_medicine is null
       or not exists (select 1 from public.medicines where id = v_medicine and is_active) then
      raise exception 'Medicine not found or inactive' using errcode = '22023';
    end if;

    v_qty := (v_row ->> 'quantity')::int;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantity must be greater than zero' using errcode = '22023';
    end if;

    v_expiry := nullif(btrim(coalesce(v_row ->> 'expiry_date', '')), '')::date;
    if v_expiry is null or v_expiry <= current_date then
      raise exception 'Expiry date must be in the future' using errcode = '22023';
    end if;

    v_cost := coalesce(nullif(btrim(coalesce(v_row ->> 'unit_cost', '')), '')::numeric, 0);
    if v_cost < 0 then
      raise exception 'Cost must not be negative' using errcode = '22023';
    end if;

    v_batch := nullif(btrim(coalesce(v_row ->> 'batch_no', '')), '');
    if v_batch is not null then
      if v_batch = any(v_seen) then
        raise exception 'Duplicate batch number % in this request', v_batch using errcode = '22023';
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

  -- Write pass.
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
-- 4. Branch-scoped reorder suggestions (PostgREST view, exactly these columns).
--    Available stock excludes anything expiring in the next 30 days; those
--    quantities are reported separately as expiring_qty instead.
-- ---------------------------------------------------------------------------
create or replace view public.v_reorder_suggestions with (security_invoker = true) as
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
where b.is_active
  and m.is_active
  and (coalesce(s.available_qty, 0) <= m.reorder_level or coalesce(s.expiring_qty, 0) > 0);

revoke all on table public.v_reorder_suggestions from public, anon;
grant select on table public.v_reorder_suggestions to authenticated;

-- ---------------------------------------------------------------------------
-- 5. create_draft_purchase_orders — one draft PO per supplier, lines grouped.
--    All lines are validated before the first write so a blank supplier (or
--    any other bad line) aborts the complete call.
-- ---------------------------------------------------------------------------
create or replace function public.create_draft_purchase_orders(
  p_branch uuid,
  p_lines jsonb
) returns uuid[]
language plpgsql security definer set search_path = public as $$
declare
  v_line jsonb;
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

  -- Validation pass.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if nullif(btrim(coalesce(v_line ->> 'supplier_id', '')), '') is null then
      raise exception 'Choose supplier for every order line' using errcode = '22023';
    end if;
    v_supplier := (v_line ->> 'supplier_id')::uuid;
    if v_supplier is null
       or not exists (select 1 from public.suppliers where id = v_supplier and is_active) then
      raise exception 'Supplier not found' using errcode = '22023';
    end if;

    v_medicine := nullif(btrim(coalesce(v_line ->> 'medicine_id', '')), '')::uuid;
    if v_medicine is null
       or not exists (select 1 from public.medicines where id = v_medicine and is_active) then
      raise exception 'Medicine not found or inactive' using errcode = '22023';
    end if;

    v_qty := (v_line ->> 'quantity')::int;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantity must be greater than zero' using errcode = '22023';
    end if;

    v_cost := (v_line ->> 'unit_cost')::numeric;
    if v_cost is null or v_cost < 0 then
      raise exception 'Unit cost must not be negative' using errcode = '22023';
    end if;

    v_lines := v_lines || jsonb_build_object(
      'supplier_id', v_supplier::text,
      'medicine_id', v_medicine::text,
      'quantity', v_qty,
      'unit_cost', v_cost);
  end loop;

  begin
    -- Mirrors the other purchase-order RPCs: bypass the status/receipt guards
    -- while we write, then reset the flag before returning.
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

-- ---------------------------------------------------------------------------
-- 6. RPC/view grants: PostgREST's authenticated role only.
-- ---------------------------------------------------------------------------
revoke all on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) from public, anon;
grant execute on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid) to authenticated;

revoke all on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid, text) from public, anon;
grant execute on function public.add_stock_batch(uuid, uuid, text, date, int, numeric, uuid, text) to authenticated;

revoke all on function public.add_opening_stock(uuid, jsonb) from public, anon;
grant execute on function public.add_opening_stock(uuid, jsonb) to authenticated;

revoke all on function public.create_draft_purchase_orders(uuid, jsonb) from public, anon;
grant execute on function public.create_draft_purchase_orders(uuid, jsonb) to authenticated;
