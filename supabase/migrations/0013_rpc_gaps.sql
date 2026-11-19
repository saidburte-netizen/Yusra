-- 0013 — Proposed RPC gap fill: void_sale and process_sale_return.
--
-- NOT YET APPLIED — owner review required. The owner's original 11 SQL steps
-- created create_sale but omitted the two RPCs the app and smoke test need.
-- This file is additive and idempotent (create or replace) and changes no
-- table structure. Run it in the Supabase SQL Editor after 0001..0011.
--
-- RUN IN SUPABASE SQL EDITOR — purpose: add void and return RPCs that restore
-- stock through the same audited movement ledger as create_sale.

create or replace function void_sale(p_sale uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sale sales%rowtype;
  v_item sale_items%rowtype;
begin
  if not has_role('super_admin','admin','pharmacist') then
    raise exception 'Only a pharmacist or admin can void a sale';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'A void reason is required';
  end if;

  select * into v_sale from sales where id = p_sale for update;
  if not found then raise exception 'Sale not found'; end if;
  if not can_access_branch(v_sale.branch_id) then raise exception 'Branch not allowed'; end if;
  if v_sale.status <> 'completed' then raise exception 'Only a completed sale can be voided'; end if;

  for v_item in select * from sale_items where sale_id = p_sale loop
    if v_item.batch_id is not null then
      update stock_batches
      set quantity = quantity + (v_item.quantity - v_item.returned_qty), updated_at = now()
      where id = v_item.batch_id;
      insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reference_type, reference_id, reason)
      values (v_sale.branch_id, v_item.medicine_id, v_item.batch_id, 'void_restore',
              v_item.quantity - v_item.returned_qty, 'sale', p_sale, p_reason);
    end if;
  end loop;

  update sales
  set status = 'voided', voided_at = now(), voided_by = auth.uid(), void_reason = p_reason
  where id = p_sale;

  update prescriptions set status = 'pending', dispensed_by = null, updated_at = now()
  where id = v_sale.prescription_id and status = 'dispensed' and dispensed_by = v_sale.cashier_id;
end $$;

create or replace function process_sale_return(
  p_sale uuid,
  p_items jsonb,
  p_reason text,
  p_refund_method payment_method default 'cash'
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_sale_id uuid := p_sale;
  v_reason text := p_reason;
  v_method payment_method := coalesce(p_refund_method, 'cash');
  v_sale sales%rowtype;
  v_line jsonb;
  v_item sale_items%rowtype;
  v_qty int;
  v_restock boolean;
  v_return_id uuid := gen_random_uuid();
  v_amount numeric(14,2) := 0;
  v_amount_due numeric(14,2) := 0;
  v_remaining int;
begin
  -- Sale returns are edit rights for S/A/P only; cashiers have view on sales.
  if not has_role('super_admin','admin','pharmacist') then
    raise exception 'You are not allowed to process returns';
  end if;
  if coalesce(trim(v_reason), '') = '' then raise exception 'A return reason is required'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Select at least one item to return';
  end if;

  select * into v_sale from sales where id = v_sale_id for update;
  if not found then raise exception 'Sale not found'; end if;
  if not can_access_branch(v_sale.branch_id) then raise exception 'Branch not allowed'; end if;
  if v_sale.status in ('voided','returned') then raise exception 'This sale cannot be returned'; end if;

  insert into sale_returns (id, return_no, sale_id, branch_id, processed_by, reason, refund_method)
  values (v_return_id, next_doc_no('RET', v_sale.branch_id), v_sale_id, v_sale.branch_id, auth.uid(), v_reason, v_method);

  for v_line in select value from jsonb_array_elements(p_items) loop
    select * into v_item from sale_items
      where id = (v_line->>'sale_item_id')::uuid and sale_id = v_sale_id for update;
    if not found then raise exception 'Item does not belong to this sale'; end if;

    v_qty := coalesce((v_line->>'quantity')::int, 0);
    v_restock := coalesce((v_line->>'restock')::boolean, true);
    v_remaining := v_item.quantity - v_item.returned_qty;
    if v_qty <= 0 or v_qty > v_remaining then
      raise exception 'Invalid return quantity for %', v_item.medicine_name;
    end if;

    update sale_items set returned_qty = returned_qty + v_qty where id = v_item.id;

    if v_restock and v_item.batch_id is not null then
      update stock_batches
      set quantity = quantity + v_qty, updated_at = now()
      where id = v_item.batch_id;
      insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reference_type, reference_id, reason)
      values (v_sale.branch_id, v_item.medicine_id, v_item.batch_id, 'sale_return', v_qty,
              'sale_return', v_return_id, v_reason);
    end if;

    v_amount := round(v_item.line_total * v_qty / v_item.quantity, 2);
    v_amount_due := v_amount_due + v_amount;

    insert into sale_return_items (return_id, sale_item_id, quantity, amount, restocked)
    values (v_return_id, v_item.id, v_qty, v_amount, v_restock);
  end loop;

  update sale_returns set refund_amount = v_amount_due where id = v_return_id;

  select count(*) into v_remaining
  from sale_items where sale_id = v_sale_id and returned_qty < quantity;
  update sales set status = case when v_remaining = 0 then 'returned' else 'partially_returned' end
  where id = v_sale_id;

  return v_return_id;
end $$;

revoke execute on function void_sale(uuid, text) from anon;
revoke execute on function process_sale_return(uuid, jsonb, text, payment_method) from anon;
grant execute on function void_sale(uuid, text) to authenticated;
grant execute on function process_sale_return(uuid, jsonb, text, payment_method) to authenticated;
