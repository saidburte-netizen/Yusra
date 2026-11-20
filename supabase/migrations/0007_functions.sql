create or replace function add_stock_batch(
  p_branch uuid,
  p_medicine uuid,
  p_batch_no text,
  p_expiry date,
  p_quantity int,
  p_cost numeric default 0,
  p_supplier uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not has_role('super_admin','admin','pharmacist','store_keeper') then
    raise exception 'You are not allowed to add stock';
  end if;
  if not can_access_branch(p_branch) then raise exception 'Branch not allowed'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_expiry is null or p_expiry <= current_date then raise exception 'Expiry date must be in the future'; end if;
  if coalesce(trim(p_batch_no), '') = '' then raise exception 'Batch number is required'; end if;

  insert into stock_batches (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price, supplier_id)
  values (p_branch, p_medicine, trim(p_batch_no), p_expiry, p_quantity, p_quantity, coalesce(p_cost, 0), p_supplier)
  on conflict (branch_id, medicine_id, batch_no) do update
    set quantity = stock_batches.quantity + excluded.quantity,
        initial_quantity = stock_batches.initial_quantity + excluded.quantity,
        updated_at = now()
  returning id into v_id;

  insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reason)
  values (p_branch, p_medicine, v_id, 'opening', p_quantity, 'Stock added manually');

  return v_id;
end $$;

create or replace function adjust_stock(
  p_batch uuid,
  p_change int,
  p_type movement_type,
  p_reason text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_b stock_batches%rowtype;
begin
  if not has_role('super_admin','admin','pharmacist','store_keeper') then
    raise exception 'You are not allowed to adjust stock';
  end if;
  if p_type not in ('adjustment','expired_writeoff','damage') then raise exception 'Invalid adjustment type'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required'; end if;
  if p_change is null or p_change = 0 then raise exception 'The change must not be zero'; end if;

  select * into v_b from stock_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found'; end if;
  if not can_access_branch(v_b.branch_id) then raise exception 'Branch not allowed'; end if;
  if p_type in ('expired_writeoff','damage') and p_change > 0 then raise exception 'Write-offs must be negative'; end if;
  if v_b.quantity + p_change < 0 then raise exception 'Not enough stock in this batch'; end if;

  update stock_batches set quantity = quantity + p_change, updated_at = now() where id = p_batch;

  insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reason)
  values (v_b.branch_id, v_b.medicine_id, p_batch, p_type, p_change, p_reason);
end $$;

create or replace function receive_purchase_order(p_po uuid, p_items jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_po purchase_orders%rowtype;
  v_line purchase_order_items%rowtype;
  v_it jsonb;
  v_qty int;
  v_batch uuid;
  v_any boolean := false;
begin
  if not has_role('super_admin','admin','pharmacist','store_keeper') then
    raise exception 'You are not allowed to receive goods';
  end if;
  select * into v_po from purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found'; end if;
  if not can_access_branch(v_po.branch_id) then raise exception 'Branch not allowed'; end if;
  if v_po.status not in ('ordered','partially_received') then
    raise exception 'This purchase order is not open for receiving';
  end if;

  perform set_config('app.via_rpc', '1', true);

  for v_it in select value from jsonb_array_elements(p_items) loop
    v_qty := coalesce((v_it->>'quantity')::int, 0);
    continue when v_qty = 0;
    if v_qty < 0 then raise exception 'Quantity cannot be negative'; end if;

    select * into v_line from purchase_order_items
      where id = (v_it->>'po_item_id')::uuid and po_id = p_po for update;
    if not found then raise exception 'Line does not belong to this order'; end if;
    if v_qty > v_line.quantity_ordered - v_line.quantity_received then
      raise exception 'Received quantity is more than the quantity still due';
    end if;
    if coalesce(trim(v_it->>'batch_no'), '') = '' then raise exception 'Batch number is required'; end if;
    if (v_it->>'expiry_date')::date <= current_date then raise exception 'Expiry date must be in the future'; end if;

    insert into stock_batches (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price, supplier_id, purchase_order_id)
    values (v_po.branch_id, v_line.medicine_id, trim(v_it->>'batch_no'), (v_it->>'expiry_date')::date, v_qty, v_qty, v_line.unit_cost, v_po.supplier_id, p_po)
    on conflict (branch_id, medicine_id, batch_no) do update
      set quantity = stock_batches.quantity + excluded.quantity,
          initial_quantity = stock_batches.initial_quantity + excluded.quantity,
          cost_price = excluded.cost_price,
          updated_at = now()
    returning id into v_batch;

    insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reference_type, reference_id)
    values (v_po.branch_id, v_line.medicine_id, v_batch, 'purchase', v_qty, 'purchase_order', p_po);

    update purchase_order_items set quantity_received = quantity_received + v_qty where id = v_line.id;
    update medicines set cost_price = v_line.unit_cost, updated_at = now() where id = v_line.medicine_id;
    v_any := true;
  end loop;

  if not v_any then raise exception 'Nothing to receive'; end if;

  update purchase_orders
  set status = case
        when exists (select 1 from purchase_order_items where po_id = p_po and quantity_received < quantity_ordered)
        then 'partially_received'::po_status
        else 'received'::po_status
      end,
      updated_at = now()
  where id = p_po;
end $$;create or replace function open_shift(p_branch uuid, p_opening_cash numeric default 0)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not has_role('super_admin','admin','pharmacist','cashier') then
    raise exception 'You are not allowed to open a shift';
  end if;
  if not can_access_branch(p_branch) then raise exception 'Branch not allowed'; end if;
  if coalesce(p_opening_cash, 0) < 0 then raise exception 'Opening cash cannot be negative'; end if;
  if exists (select 1 from shifts where cashier_id = auth.uid() and status = 'open') then
    raise exception 'You already have an open shift';
  end if;
  insert into shifts (branch_id, cashier_id, opening_cash)
  values (p_branch, auth.uid(), coalesce(p_opening_cash, 0))
  returning id into v_id;
  return v_id;
end $$;

create or replace function close_shift(p_shift uuid, p_closing_cash numeric, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_s shifts%rowtype;
  v_cash numeric := 0;
  v_change numeric := 0;
  v_refunds numeric := 0;
  v_expected numeric;
begin
  select * into v_s from shifts where id = p_shift for update;
  if not found then raise exception 'Shift not found'; end if;
  if v_s.status <> 'open' then raise exception 'This shift is already closed'; end if;
  if not (v_s.cashier_id = auth.uid() or has_role('super_admin','admin')) then
    raise exception 'You are not allowed to close this shift';
  end if;
  if not can_access_branch(v_s.branch_id) then raise exception 'Branch not allowed'; end if;
  if p_closing_cash is null or p_closing_cash < 0 then raise exception 'Enter the counted cash'; end if;

  select coalesce(sum(sp.amount), 0) into v_cash
  from sale_payments sp join sales s on s.id = sp.sale_id
  where s.shift_id = p_shift and s.status <> 'voided' and sp.method = 'cash';

  select coalesce(sum(change_due), 0) into v_change
  from sales where shift_id = p_shift and status <> 'voided';

  select coalesce(sum(r.refund_amount), 0) into v_refunds
  from sale_returns r join sales s on s.id = r.sale_id
  where s.shift_id = p_shift and r.refund_method = 'cash';

  v_expected := v_s.opening_cash + v_cash - v_change - v_refunds;

  update shifts
  set status = 'closed', closed_at = now(), expected_cash = v_expected,
      closing_cash = p_closing_cash, difference = p_closing_cash - v_expected, note = p_note
  where id = p_shift;

  return jsonb_build_object('expected_cash', v_expected, 'closing_cash', p_closing_cash, 'difference', p_closing_cash - v_expected);
end $$;

create or replace function create_sale(
  p_branch uuid,
  p_shift uuid,
  p_customer uuid,
  p_prescription uuid,
  p_items jsonb,
  p_payments jsonb,
  p_discount numeric default 0,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_sale uuid := gen_random_uuid();
  v_shift shifts%rowtype;
  v_item jsonb;
  v_pay jsonb;
  v_med medicines%rowtype;
  v_batch stock_batches%rowtype;
  v_need int;
  v_take int;
  v_line numeric(14,2);
  v_line_tax numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2);
  v_paid numeric(14,2) := 0;
  v_has_cash boolean := false;
  v_vat numeric;
  v_max_pct numeric;
  v_amount numeric;
  v_discount numeric(14,2) := coalesce(p_discount, 0);
begin
  if not has_role('super_admin','admin','pharmacist','cashier') then
    raise exception 'You are not allowed to make sales';
  end if;
  if not can_access_branch(p_branch) then raise exception 'Branch not allowed'; end if;

  select * into v_shift from shifts where id = p_shift and status = 'open' and branch_id = p_branch;
  if not found then raise exception 'Open a shift before selling'; end if;
  if v_shift.cashier_id <> auth.uid() then raise exception 'This shift belongs to another user'; end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'The cart is empty';
  end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then
    raise exception 'Add at least one payment';
  end if;

  v_vat := coalesce((select (value #>> '{}')::numeric from app_settings where key = 'vat_rate'), 0.15);
  v_max_pct := coalesce((select (value #>> '{}')::numeric from app_settings where key = 'max_cashier_discount_pct'), 5);

  insert into sales (id, invoice_no, branch_id, shift_id, cashier_id, customer_id, prescription_id, note)
  values (v_sale, next_doc_no('INV', p_branch), p_branch, p_shift, auth.uid(), p_customer, p_prescription, p_note);

  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_med from medicines where id = (v_item->>'medicine_id')::uuid and is_active;
    if not found then raise exception 'Medicine not found or inactive'; end if;

    v_need := coalesce((v_item->>'quantity')::int, 0);
    if v_need <= 0 then raise exception 'Invalid quantity for %', v_med.name; end if;
    if v_med.requires_prescription and p_prescription is null then
      raise exception '% needs a prescription', v_med.name;
    end if;

    for v_batch in
      select * from stock_batches
      where branch_id = p_branch and medicine_id = v_med.id
        and is_active and quantity > 0 and expiry_date > current_date
      order by expiry_date, received_at
      for update
    loop
      exit when v_need = 0;
      v_take := least(v_need, v_batch.quantity);
      v_line := round(v_take * v_med.selling_price, 2);
      v_line_tax := case when v_med.vat_applicable then round(v_line * v_vat, 2) else 0 end;

      insert into sale_items (sale_id, medicine_id, batch_id, medicine_name, batch_no, expiry_date, quantity, unit_price, cost_price, line_total, tax)
      values (v_sale, v_med.id, v_batch.id, v_med.name, v_batch.batch_no, v_batch.expiry_date, v_take, v_med.selling_price, v_batch.cost_price, v_line, v_line_tax);

      update stock_batches set quantity = quantity - v_take, updated_at = now() where id = v_batch.id;

      insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reference_type, reference_id)
      values (p_branch, v_med.id, v_batch.id, 'sale', -v_take, 'sale', v_sale);

      v_subtotal := v_subtotal + v_line;
      v_tax := v_tax + v_line_tax;
      v_need := v_need - v_take;
    end loop;

    if v_need > 0 then
      raise exception 'Not enough in-date stock for % (short by %)', v_med.name, v_need;
    end if;
  end loop;

  if v_discount < 0 or v_discount > v_subtotal then raise exception 'Invalid discount'; end if;
  if my_role() = 'cashier' and v_discount > round(v_subtotal * v_max_pct / 100, 2) then
    raise exception 'Discount is above your limit of % percent', v_max_pct;
  end if;

  v_total := v_subtotal + v_tax - v_discount;

  for v_pay in select value from jsonb_array_elements(p_payments) loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Invalid payment amount'; end if;
    insert into sale_payments (sale_id, method, amount, reference)
    values (v_sale, (v_pay->>'method')::payment_method, v_amount, nullif(v_pay->>'reference', ''));
    if (v_pay->>'method') = 'cash' then v_has_cash := true; end if;
    v_paid := v_paid + v_amount;
  end loop;

  if v_paid < v_total then raise exception 'Payment is less than the total'; end if;
  if v_paid > v_total and not v_has_cash then raise exception 'Only cash payments can have change'; end if;

  update sales
  set subtotal = v_subtotal, discount = v_discount, tax = v_tax, total = v_total,
      paid = v_paid, change_due = v_paid - v_total
  where id = v_sale;

  if v_discount > 0 and v_subtotal > 0 then
    update sale_items set discount_share = round(line_total / v_subtotal * v_discount, 2) where sale_id = v_sale;
  end if;

  if p_prescription is not null then
    update prescriptions
    set status = 'dispensed', dispensed_by = auth.uid(), updated_at = now()
    where id = p_prescription and branch_id = p_branch and status = 'pending';
    if not found then raise exception 'The prescription is not valid for dispensing'; end if;
  end if;

  return v_sale;
end $$;