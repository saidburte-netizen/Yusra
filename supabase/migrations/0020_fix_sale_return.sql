-- 0020 — Fix process_sale_return() from 0013.
--
-- Bug: the final UPDATE assigned a CASE expression whose branches were plain
-- text to a sale_status column. PostgreSQL rejects that at runtime with
-- "column status is of type sale_status but expression is of type text", so
-- every return failed after the stock had already been restored.
--
-- Fix: cast both CASE branches to sale_status. The rest of the body is the
-- exact implementation from 0013_rpc_gaps.sql, including permission checks,
-- per-line validation, restocking, movement ledger and refund calculation.
-- This file is additive and idempotent (create or replace) and changes no
-- table structure.

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
  update sales
  set status = case
    when v_remaining = 0 then 'returned'::sale_status
    else 'partially_returned'::sale_status
  end
  where id = v_sale_id;

  return v_return_id;
end $$;

revoke all on function process_sale_return(uuid, jsonb, text, payment_method) from public, anon;
grant execute on function process_sale_return(uuid, jsonb, text, payment_method) to authenticated;
