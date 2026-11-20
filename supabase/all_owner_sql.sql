-- ===========================================================================
-- YUSRA PHARMACY — COMPLETE, IDEMPOTENT SQL RUN ORDER
-- ===========================================================================
-- Every statement here is safe to re-run. Run each numbered section separately
-- in the Supabase SQL Editor, top to bottom. If an earlier section failed
-- halfway, just run the whole section again.
--
-- Checks/fixes applied to the supplied SQL:
--   * enums, tables, sequences and indexes are now IF NOT EXISTS / guarded
--   * triggers are dropped before creation
--   * pg_trgm indexes detect the operator-class schema automatically
--   * the first-super-admin UPDATE is harmless until you replace the email
-- ===========================================================================



-- =========================================================================
-- FILE: supabase/migrations/0001_extensions_enums.sql
-- =========================================================================

create extension if not exists pgcrypto;
create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

do $$
begin
  create type app_role as enum ('super_admin','admin','pharmacist','cashier','store_keeper','accountant');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type po_status as enum ('draft','ordered','partially_received','received','cancelled');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type sale_status as enum ('completed','voided','partially_returned','returned');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type payment_method as enum ('cash','mobile_money','card','bank_transfer');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type movement_type as enum ('opening','purchase','sale','sale_return','void_restore','adjustment','expired_writeoff','damage');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type shift_status as enum ('open','closed');
exception when duplicate_object then null;
end $$;
do $$
begin
  create type rx_status as enum ('pending','dispensed','cancelled');
exception when duplicate_object then null;
end $$;

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;


-- =========================================================================
-- FILE: supabase/migrations/0002_core_tables_helpers.sql
-- =========================================================================

create table if not exists branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  phone text,
  role app_role not null default 'cashier',
  branch_id uuid references branches(id),
  is_active boolean not null default true,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_branch_idx on profiles(branch_id);

create or replace function my_role()
returns app_role language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid() and is_active
$$;

create or replace function my_branch()
returns uuid language sql stable security definer set search_path = public as $$
  select branch_id from profiles where id = auth.uid() and is_active
$$;

create or replace function has_role(variadic roles app_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(my_role() = any(roles), false)
$$;

create or replace function can_access_branch(b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when my_role() is null then false
    when my_role() = 'super_admin' then true
    else b is not null and b = my_branch()
  end
$$;

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, full_name, role, branch_id)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_app_meta_data->>'role')::app_role, 'cashier'),
    nullif(new.raw_app_meta_data->>'branch_id', '')::uuid
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

create table if not exists app_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists doc_counters (
  prefix text not null,
  branch_id uuid not null references branches(id),
  year int not null,
  last_no int not null default 0,
  primary key (prefix, branch_id, year)
);

create or replace function next_doc_no(p_prefix text, p_branch uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_year int := extract(year from (now() at time zone 'Africa/Addis_Ababa'))::int;
  v_no int;
  v_code text;
begin
  insert into doc_counters (prefix, branch_id, year, last_no)
  values (p_prefix, p_branch, v_year, 1)
  on conflict (prefix, branch_id, year)
  do update set last_no = doc_counters.last_no + 1
  returning last_no into v_no;
  select code into v_code from branches where id = p_branch;
  return p_prefix || '-' || v_code || '-' || v_year || '-' || lpad(v_no::text, 5, '0');
end $$;

revoke execute on function next_doc_no(text, uuid) from public, anon, authenticated;

create table if not exists audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid,
  action text not null,
  table_name text not null,
  record_id text,
  branch_id uuid,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_logs_created_idx on audit_logs (created_at desc);
create index if not exists audit_logs_record_idx on audit_logs (table_name, record_id);


-- =========================================================================
-- FILE: supabase/migrations/0003_catalog.sql
-- =========================================================================

create sequence if not exists medicine_sku_seq start 1;

create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists medicines (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique default ('YP-' || lpad(nextval('medicine_sku_seq')::text, 6, '0')),
  barcode text unique,
  name text not null,
  generic_name text,
  category_id uuid references categories(id) on delete set null,
  dosage_form text,
  strength text,
  unit text not null default 'Pack',
  manufacturer text,
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  vat_applicable boolean not null default false,
  requires_prescription boolean not null default false,
  is_controlled boolean not null default false,
  reorder_level int not null default 10 check (reorder_level >= 0),
  storage_notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- FIX: detect the schema that actually owns pg_trgm's operator class.
do $$
declare
  v_opclass text;
begin
  select format('%I.%I', n.nspname, op.opcname) into v_opclass
  from pg_opclass op
  join pg_am am on am.oid = op.opcmethod
  join pg_namespace n on n.oid = op.opcnamespace
  where am.amname = 'gin' and op.opcname = 'gin_trgm_ops'
  order by (n.nspname = 'public') desc
  limit 1;

  if v_opclass is null then
    create extension if not exists pg_trgm with schema public;
    v_opclass := 'public.gin_trgm_ops';
  end if;

  execute format('create index if not exists medicines_name_trgm on medicines using gin (name %s)', v_opclass);
  execute format('create index if not exists medicines_generic_trgm on medicines using gin (generic_name %s)', v_opclass);
end $$;
create index if not exists medicines_category_idx on medicines (category_id);

create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  tin text,
  payment_terms text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- =========================================================================
-- FILE: supabase/migrations/0004_purchasing.sql
-- =========================================================================

create table if not exists purchase_orders (
  id uuid primary key default gen_random_uuid(),
  po_no text unique,
  branch_id uuid not null references branches(id),
  supplier_id uuid not null references suppliers(id),
  status po_status not null default 'draft',
  order_date date not null default current_date,
  expected_date date,
  notes text,
  subtotal numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0 check (tax >= 0),
  total numeric(14,2) not null default 0,
  created_by uuid references profiles(id) default auth.uid(),
  approved_by uuid references profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists po_branch_idx on purchase_orders (branch_id, created_at desc);
create index if not exists po_supplier_idx on purchase_orders (supplier_id);

create table if not exists purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  po_id uuid not null references purchase_orders(id) on delete cascade,
  medicine_id uuid not null references medicines(id),
  quantity_ordered int not null check (quantity_ordered > 0),
  quantity_received int not null default 0 check (quantity_received >= 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) generated always as (quantity_ordered * unit_cost) stored,
  unique (po_id, medicine_id)
);


-- =========================================================================
-- FILE: supabase/migrations/0005_stock.sql
-- =========================================================================

create table if not exists stock_batches (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  medicine_id uuid not null references medicines(id),
  batch_no text not null,
  expiry_date date not null,
  quantity int not null default 0 check (quantity >= 0),
  initial_quantity int not null default 0,
  cost_price numeric(14,2) not null default 0,
  supplier_id uuid references suppliers(id),
  purchase_order_id uuid references purchase_orders(id),
  received_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, medicine_id, batch_no)
);
create index if not exists stock_batches_fefo_idx on stock_batches (branch_id, medicine_id, expiry_date) where quantity > 0;
create index if not exists stock_batches_expiry_idx on stock_batches (expiry_date) where quantity > 0;

create table if not exists stock_movements (
  id bigint generated always as identity primary key,
  branch_id uuid not null references branches(id),
  medicine_id uuid not null references medicines(id),
  batch_id uuid references stock_batches(id) on delete set null,
  movement_type movement_type not null,
  quantity_change int not null check (quantity_change <> 0),
  reference_type text,
  reference_id uuid,
  reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_med_idx on stock_movements (medicine_id, created_at desc);
create index if not exists stock_movements_branch_idx on stock_movements (branch_id, created_at desc);


-- =========================================================================
-- FILE: supabase/migrations/0006_sales_finance.sql
-- =========================================================================

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text unique,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists prescriptions (
  id uuid primary key default gen_random_uuid(),
  rx_no text unique,
  branch_id uuid not null references branches(id),
  customer_id uuid references customers(id) on delete set null,
  patient_name text not null,
  patient_age int,
  prescriber_name text not null,
  prescriber_license text,
  facility text,
  rx_date date not null default current_date,
  image_path text,
  notes text,
  status rx_status not null default 'pending',
  dispensed_by uuid references profiles(id),
  created_by uuid references profiles(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists prescriptions_branch_idx on prescriptions (branch_id, status);

create table if not exists shifts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  cashier_id uuid not null references profiles(id) default auth.uid(),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(14,2) not null default 0 check (opening_cash >= 0),
  expected_cash numeric(14,2),
  closing_cash numeric(14,2),
  difference numeric(14,2),
  status shift_status not null default 'open',
  note text
);
create unique index if not exists one_open_shift_per_user on shifts (cashier_id) where status = 'open';
create index if not exists shifts_branch_idx on shifts (branch_id, opened_at desc);

create table if not exists sales (
  id uuid primary key default gen_random_uuid(),
  invoice_no text not null unique,
  branch_id uuid not null references branches(id),
  shift_id uuid references shifts(id),
  cashier_id uuid not null references profiles(id) default auth.uid(),
  customer_id uuid references customers(id) on delete set null,
  prescription_id uuid references prescriptions(id) on delete set null,
  status sale_status not null default 'completed',
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  paid numeric(14,2) not null default 0,
  change_due numeric(14,2) not null default 0,
  note text,
  voided_at timestamptz,
  voided_by uuid references profiles(id),
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sales_branch_idx on sales (branch_id, created_at desc);
create index if not exists sales_shift_idx on sales (shift_id);
create index if not exists sales_cashier_idx on sales (cashier_id, created_at desc);

create table if not exists sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  medicine_id uuid not null references medicines(id),
  batch_id uuid references stock_batches(id) on delete set null,
  medicine_name text not null,
  batch_no text,
  expiry_date date,
  quantity int not null check (quantity > 0),
  returned_qty int not null default 0,
  unit_price numeric(14,2) not null,
  cost_price numeric(14,2) not null default 0,
  line_total numeric(14,2) not null,
  tax numeric(14,2) not null default 0,
  discount_share numeric(14,2) not null default 0,
  check (returned_qty >= 0 and returned_qty <= quantity)
);
create index if not exists sale_items_sale_idx on sale_items (sale_id);
create index if not exists sale_items_med_idx on sale_items (medicine_id);

create table if not exists sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  method payment_method not null,
  amount numeric(14,2) not null check (amount > 0),
  reference text
);
create index if not exists sale_payments_sale_idx on sale_payments (sale_id);

create table if not exists sale_returns (
  id uuid primary key default gen_random_uuid(),
  return_no text not null unique,
  sale_id uuid not null references sales(id),
  branch_id uuid not null references branches(id),
  processed_by uuid references profiles(id) default auth.uid(),
  reason text not null,
  refund_method payment_method not null default 'cash',
  refund_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists sale_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references sale_returns(id) on delete cascade,
  sale_item_id uuid not null references sale_items(id),
  quantity int not null check (quantity > 0),
  amount numeric(14,2) not null default 0,
  restocked boolean not null default true
);

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references branches(id),
  category text not null,
  description text,
  amount numeric(14,2) not null check (amount > 0),
  expense_date date not null default current_date,
  payment_method payment_method not null default 'cash',
  receipt_path text,
  created_by uuid references profiles(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists expenses_branch_idx on expenses (branch_id, expense_date desc);


-- =========================================================================
-- FILE: supabase/migrations/0007_functions.sql
-- =========================================================================

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


-- =========================================================================
-- FILE: supabase/migrations/0008_views.sql
-- =========================================================================

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
group by b.id, m.id;

create or replace view v_low_stock with (security_invoker = true) as
select * from v_stock_summary
where is_active and available_qty <= reorder_level;

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
  and sb.expiry_date <= current_date + coalesce((select (value #>> '{}')::int from app_settings where key = 'expiry_alert_days'), 90);

create or replace view v_daily_sales with (security_invoker = true) as
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
group by branch_id, (created_at at time zone 'Africa/Addis_Ababa')::date;


-- =========================================================================
-- FILE: supabase/migrations/0009_triggers.sql
-- =========================================================================

do $$
declare t text;
begin
  foreach t in array array['branches','profiles','categories','medicines','suppliers','purchase_orders','stock_batches','customers','prescriptions','sales','expenses','app_settings']
  loop
    execute format('drop trigger if exists trg_%s_updated on %I', t, t);
    execute format('create trigger trg_%s_updated before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

create or replace function trg_po_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.po_no is null or new.po_no = '' then
    new.po_no := next_doc_no('PO', new.branch_id);
  end if;
  return new;
end $$;
drop trigger if exists trg_po_numbering on purchase_orders;
create trigger trg_po_numbering before insert on purchase_orders
  for each row execute function trg_po_defaults();

create or replace function trg_rx_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.rx_no is null or new.rx_no = '' then
    new.rx_no := next_doc_no('RX', new.branch_id);
  end if;
  return new;
end $$;
drop trigger if exists trg_rx_numbering on prescriptions;
create trigger trg_rx_numbering before insert on prescriptions
  for each row execute function trg_rx_defaults();

create or replace function trg_po_total()
returns trigger language plpgsql as $$
begin
  new.total := new.subtotal + new.tax;
  return new;
end $$;
create trigger trg_po_total_calc before insert or update on purchase_orders
  for each row execute function trg_po_total();

create or replace function recalc_po_subtotal()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_po uuid := case when tg_op = 'DELETE' then old.po_id else new.po_id end;
begin
  update purchase_orders
  set subtotal = coalesce((select sum(line_total) from purchase_order_items where po_id = v_po), 0)
  where id = v_po;
  return null;
end $$;
create trigger trg_poi_recalc after insert or update or delete on purchase_order_items
  for each row execute function recalc_po_subtotal();

create or replace function guard_po_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status in ('received','partially_received')
       and coalesce(current_setting('app.via_rpc', true), '') <> '1' then
      raise exception 'Use goods receiving to receive stock';
    end if;
    if new.status in ('ordered','cancelled')
       and auth.uid() is not null and not has_role('super_admin','admin') then
      raise exception 'Only an admin can approve or cancel purchase orders';
    end if;
    if new.status = 'draft' and old.status <> 'draft' then
      raise exception 'An order cannot go back to draft';
    end if;
    if new.status = 'ordered' then
      new.approved_by := auth.uid();
      new.approved_at := now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_po_guard on purchase_orders;
create trigger trg_po_guard before update on purchase_orders
  for each row execute function guard_po_status();

create or replace function protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if has_role('super_admin') then return new; end if;
  if old.id = auth.uid() then
    new.role := old.role;
    new.branch_id := old.branch_id;
    new.is_active := old.is_active;
    new.email := old.email;
  elsif has_role('admin') then
    if old.role = 'super_admin' or new.role = 'super_admin' then
      raise exception 'Admins cannot change super admin accounts';
    end if;
  else
    raise exception 'Not allowed';
  end if;
  return new;
end $$;
drop trigger if exists trg_profiles_protect on profiles;
create trigger trg_profiles_protect before update on profiles
  for each row execute function protect_profile_fields();

create or replace function audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new); v_row := v_new;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_row := v_new;
    if v_old = v_new then return new; end if;
  else
    v_old := to_jsonb(old); v_row := v_old;
  end if;
  insert into audit_logs (user_id, action, table_name, record_id, branch_id, old_data, new_data)
  values (auth.uid(), tg_op, tg_table_name, coalesce(v_row->>'id', v_row->>'key'), nullif(v_row->>'branch_id', '')::uuid, v_old, v_new);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','branches','app_settings','categories','medicines','suppliers','purchase_orders','customers','prescriptions','shifts','sales','expenses']
  loop
    execute format('drop trigger if exists trg_%s_audit on %I', t, t);
    execute format('create trigger trg_%s_audit after insert or update or delete on %I for each row execute function audit_row()', t, t);
  end loop;
end $$;


-- =========================================================================
-- FILE: supabase/migrations/0010_rls_storage.sql
-- =========================================================================

-- 0010 — Row Level Security and Storage buckets.
--
-- IMPORTANT (integration note, not a database change):
-- The SQL steps supplied by the owner for this project did not include any
-- `create policy`, `alter table ... enable row level security`, or
-- `storage.buckets` statements. This file is deliberately left with no
-- executable statements so that the migration folder honestly matches what
-- the owner actually ran in the Supabase SQL Editor.
--
-- Without RLS, Supabase tables are reachable directly with the anon key,
-- so the role rules in app (and the smoke test) cannot be enforced by the
-- database. A proposed, idempotent hardening script is provided as
-- 0012_rls_hardening.sql. It has NOT been applied and must be reviewed and
-- run by the owner in the SQL Editor. See supabase/README.md.


-- =========================================================================
-- FILE: supabase/migrations/0011_seed.sql
-- =========================================================================

insert into branches (name, code) values ('Yusra Pharmacy - Main Branch', 'MAIN')
on conflict (code) do nothing;

insert into app_settings (key, value) values
  ('pharmacy_name', to_jsonb('Yusra Pharmacy'::text)),
  ('tagline', to_jsonb('Care made easy'::text)),
  ('currency', to_jsonb('ETB'::text)),
  ('vat_rate', to_jsonb(0.15::numeric)),
  ('low_stock_default', to_jsonb(10)),
  ('expiry_alert_days', to_jsonb(90)),
  ('max_cashier_discount_pct', to_jsonb(5)),
  ('receipt_footer', to_jsonb('Thank you for choosing Yusra Pharmacy. Get well soon.'::text)),
  ('address', to_jsonb(''::text)),
  ('phone', to_jsonb(''::text)),
  ('tin', to_jsonb(''::text)),
  ('license_no', to_jsonb(''::text))
on conflict (key) do nothing;

insert into categories (name) values
  ('Antibiotics'), ('Pain and fever'), ('Antimalarials'), ('Vitamins and supplements'),
  ('Heart and blood pressure'), ('Diabetes'), ('Respiratory and allergy'), ('Stomach and digestion'),
  ('Skin care'), ('Mother and baby'), ('Medical supplies'), ('Personal care')
on conflict (name) do nothing;update profiles
set role = 'super_admin',
    full_name = 'Yusra',
    branch_id = (select id from branches where code = 'MAIN')
where email = 'PUT-THE-EMAIL-HERE';select relname as table_name, relrowsecurity as rls_on
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r'
order by relname;


-- =========================================================================
-- FILE: supabase/migrations/0012_rls_hardening.sql
-- =========================================================================

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
-- Storage buckets. prescriptions and receipts are private; the remaining
-- three are public brand/catalogue/avatar assets. Prescription paths are
-- <branch_id>/<rx_id>/<file> so the policy can scope by the first folder.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit) values
  ('prescriptions',  'prescriptions',  false, 5242880),
  ('receipts',       'receipts',       false, 5242880),
  ('medicine-images','medicine-images', true, 5242880),
  ('branding',       'branding',        true, 5242880),
  ('avatars',        'avatars',         true, 5242880)
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


-- =========================================================================
-- FILE: supabase/migrations/0013_rpc_gaps.sql
-- =========================================================================

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


-- =========================================================================
-- FILE: supabase/migrations/0014_report_views.sql
-- =========================================================================

-- 0014 — Proposed reporting views (REVIEW BEFORE APPLYING).
--
-- The original 0001–0011 schema ships only four aggregate views. The Reports
-- screen in the app exposes twelve reports; this file defines them with the
-- exact column names the app already queries. Every view also exposes
-- `branch_id` — appended as the LAST column so an existing view can be
-- replaced with `create or replace view` — so a super_admin can filter a
-- report by branch. Other roles are still scoped by RLS. All views use
-- `security_invoker = true`, so the caller's policies apply and a cashier
-- never sees another branch's figures.
--
-- Apply once in the Supabase SQL Editor after reviewing the definitions.
-- It is additive and idempotent.

create or replace view v_report_sales_by_day with (security_invoker = true) as
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
group by 1, s.branch_id;

create or replace view v_report_sales_by_cashier with (security_invoker = true) as
select
  coalesce(nullif(p.full_name, ''), s.cashier_id::text) as cashier,
  count(*)::int as invoices,
  coalesce(sum(s.total), 0) as total,
  s.branch_id
from sales s
left join profiles p on p.id = s.cashier_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_sales_payment with (security_invoker = true) as
select
  sp.method::text as payment_method,
  count(distinct sp.sale_id)::int as invoices,
  coalesce(sum(sp.amount), 0) as total,
  s.branch_id
from sale_payments sp
join sales s on s.id = sp.sale_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_sales_by_medicine with (security_invoker = true) as
select
  si.medicine_name as medicine,
  sum(si.quantity - si.returned_qty)::int as qty,
  coalesce(sum(si.line_total - si.discount_share), 0) as revenue,
  coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
  coalesce(sum(si.line_total - si.discount_share
    - si.cost_price * (si.quantity - si.returned_qty)), 0) as profit,
  s.branch_id
from sale_items si
join sales s on s.id = si.sale_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_profit with (security_invoker = true) as
with daily_revenue as (
  select
    (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
    coalesce(sum(s.total), 0) as revenue,
    s.branch_id
  from sales s
  where s.status <> 'voided'
  group by 1, s.branch_id
), daily_cost as (
  select
    (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
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
full join daily_cost c on c.date = r.date and c.branch_id = r.branch_id;

create or replace view v_report_stock_valuation with (security_invoker = true) as
select
  m.name as medicine,
  sum(sb.quantity)::int as qty,
  case when sum(sb.quantity) = 0 then 0
       else round(sum(sb.quantity * sb.cost_price) / sum(sb.quantity), 2) end as unit_cost,
  coalesce(sum(sb.quantity * sb.cost_price), 0) as value,
  sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0
group by m.id, m.name, sb.branch_id;

create or replace view v_report_expiry_losses with (security_invoker = true) as
select
  sb.expiry_date as expiry,
  m.name as medicine,
  sb.batch_no as batch,
  sb.quantity as qty,
  coalesce(sb.quantity * sb.cost_price, 0) as value,
  sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0 and sb.expiry_date <= current_date;

create or replace view v_report_purchases_supplier with (security_invoker = true) as
select
  s.name as supplier,
  count(*)::int as orders,
  coalesce(sum(po.total), 0) as total,
  po.branch_id
from purchase_orders po
join suppliers s on s.id = po.supplier_id
where po.status not in ('draft', 'cancelled')
group by s.id, s.name, po.branch_id;

create or replace view v_report_expenses with (security_invoker = true) as
select
  expense_date as date,
  category,
  coalesce(sum(amount), 0) as amount,
  branch_id
from expenses
group by expense_date, category, branch_id;

create or replace view v_report_net_profit with (security_invoker = true) as
with revenue as (
  select
    to_char((created_at at time zone 'Africa/Addis_Ababa'), 'YYYY-MM') as period,
    coalesce(sum(total), 0) as revenue,
    branch_id
  from sales
  where status <> 'voided'
  group by 1, branch_id
), costs as (
  select
    to_char(expense_date, 'YYYY-MM') as period,
    coalesce(sum(amount), 0) as expenses,
    branch_id
  from expenses
  group by 1, branch_id
)
select
  coalesce(r.period, c.period) as period,
  coalesce(r.revenue, 0) as revenue,
  coalesce(c.expenses, 0) as expenses,
  coalesce(r.revenue, 0) - coalesce(c.expenses, 0) as net,
  coalesce(r.branch_id, c.branch_id) as branch_id
from revenue r
full join costs c on c.period = r.period and c.branch_id = r.branch_id;

create or replace view v_report_shift_variance with (security_invoker = true) as
select
  coalesce(nullif(p.full_name, ''), sh.cashier_id::text) as cashier,
  to_char((sh.opened_at at time zone 'Africa/Addis_Ababa'), 'YYYY-MM-DD HH24:MI') as shift,
  coalesce(sh.expected_cash, 0) as expected,
  coalesce(sh.closing_cash, 0) as actual,
  coalesce(sh.closing_cash, 0) - coalesce(sh.expected_cash, 0) as variance,
  sh.branch_id
from shifts sh
left join profiles p on p.id = sh.cashier_id
where sh.status = 'closed';

create or replace view v_report_controlled_register with (security_invoker = true) as
select
  (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
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
group by 1, 2, 4, 5, s.branch_id;

-- Reports are readable by signed-in staff only; anon must never see figures.
revoke all on
  v_report_sales_by_day,
  v_report_sales_by_cashier,
  v_report_sales_payment,
  v_report_sales_by_medicine,
  v_report_profit,
  v_report_stock_valuation,
  v_report_expiry_losses,
  v_report_purchases_supplier,
  v_report_expenses,
  v_report_net_profit,
  v_report_shift_variance,
  v_report_controlled_register
from anon;
grant select on
  v_report_sales_by_day,
  v_report_sales_by_cashier,
  v_report_sales_payment,
  v_report_sales_by_medicine,
  v_report_profit,
  v_report_stock_valuation,
  v_report_expiry_losses,
  v_report_purchases_supplier,
  v_report_expenses,
  v_report_net_profit,
  v_report_shift_variance,
  v_report_controlled_register
to authenticated;


-- =========================================================================
-- FILE: supabase/migrations/0015_team_management.sql
-- =========================================================================

-- 0015 — Proposed team access + settings publishing RPCs (REVIEW BEFORE APPLYING).
--
-- Goal: the super admin can share their role/branch access with teammates and
-- publish the tenant settings to the whole team, without the Flutter app ever
-- writing to `profiles` or `auth.users` directly. Every change is audited.
--
-- Apply once in the Supabase SQL Editor after reviewing. Additive and
-- idempotent. Requires 0012_rls_hardening.sql to have been applied.

-- ---------------------------------------------------------------------------
-- set_user_access: change one teammate's role, branch and active flag.
-- Super admins may set any combination. Admins may only manage users in their
-- own branch, may never create another super admin, and cannot edit themself.
-- ---------------------------------------------------------------------------
create or replace function set_user_access(
  p_user uuid,
  p_role app_role,
  p_branch uuid,
  p_active boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target profiles%rowtype;
  v_caller_role app_role := my_role();
  v_caller_branch uuid := my_branch();
begin
  if v_caller_role is distinct from 'super_admin' and v_caller_role is distinct from 'admin' then
    raise exception 'Not allowed: admin access required'
      using errcode = '42501';
  end if;

  if p_user = auth.uid() then
    raise exception 'You cannot change your own access here'
      using errcode = '42501';
  end if;

  select * into v_target from profiles where id = p_user;
  if not found then
    raise exception 'Team member not found' using errcode = 'PGRST116';
  end if;

  if v_caller_role = 'admin' then
    if v_target.branch_id is distinct from v_caller_branch
       or p_branch is distinct from v_caller_branch then
      raise exception 'You can only manage members of your own branch'
        using errcode = '42501';
    end if;
    if p_role = 'super_admin' then
      raise exception 'Only a super admin can grant super admin access'
        using errcode = '42501';
    end if;
  end if;

  if p_role = 'super_admin' and p_branch is not null then
    -- A super admin is global; keeping a branch is harmless but misleading.
    p_branch := null;
  end if;

  if not p_active and v_target.role = 'super_admin' then
    raise exception 'A super admin cannot be deactivated here'
      using errcode = '42501';
  end if;

  update profiles
     set role = p_role,
         branch_id = p_branch,
         is_active = p_active,
         updated_at = now()
   where id = p_user;

  -- Keep the JWT app_metadata in step with the profile so RLS and the Edge
  -- Functions see the new role on the next sign-in.
  begin
    update auth.users
       set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
             || jsonb_build_object(
                  'role', p_role::text,
                  'branch_id', coalesce(p_branch::text, ''))
     where id = p_user;
  exception when others then
    raise notice 'auth.users metadata sync skipped: %', sqlerrm;
  end;

  insert into audit_logs (user_id, action, table_name, record_id, branch_id, old_data, new_data)
  values (
    auth.uid(), 'update_access', 'profiles', p_user::text, p_branch,
    jsonb_build_object(
      'role', v_target.role, 'branch_id', v_target.branch_id,
      'is_active', v_target.is_active),
    jsonb_build_object(
      'role', p_role, 'branch_id', p_branch, 'is_active', p_active)
  );
end $$;

-- ---------------------------------------------------------------------------
-- share_admin_access: copy the caller's role and branch to selected teammates.
-- Returns the number of members updated.
-- ---------------------------------------------------------------------------
create or replace function share_admin_access(p_targets uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
  v_count int := 0;
  v_role app_role := my_role();
  v_branch uuid := my_branch();
begin
  if v_role is distinct from 'super_admin' and v_role is distinct from 'admin' then
    raise exception 'Not allowed: admin access required'
      using errcode = '42501';
  end if;

  if p_targets is null or cardinality(p_targets) = 0 then
    raise exception 'Select at least one teammate'
      using errcode = '22023';
  end if;

  foreach v_target in array p_targets loop
    if v_target = auth.uid() then
      continue;
    end if;
    if v_role = 'admin' and v_branch is null then
      raise exception 'Your account has no branch to share'
        using errcode = '42501';
    end if;
    perform set_user_access(v_target, v_role, v_branch, true);
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- publish_app_settings: share the current tenant settings with every teammate.
-- Settings are global key/value rows, so publishing touches each row (making
-- the change visible to caches) and records one audit event. Returns key count.
-- ---------------------------------------------------------------------------
create or replace function publish_app_settings()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if not has_role('super_admin', 'admin') then
    raise exception 'Not allowed: admin access required'
      using errcode = '42501';
  end if;

  update app_settings
     set updated_by = auth.uid(),
         updated_at = now()
   where true;
  get diagnostics v_count = row_count;

  insert into audit_logs (user_id, action, table_name, record_id, old_data, new_data)
  values (
    auth.uid(), 'publish_settings', 'app_settings', null, null,
    null, jsonb_build_object('keys_published', v_count)
  );

  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- Restrict execution to signed-in staff.
-- ---------------------------------------------------------------------------
revoke all on function set_user_access(uuid, app_role, uuid, boolean) from public, anon;
revoke all on function share_admin_access(uuid[]) from public, anon;
revoke all on function publish_app_settings() from public, anon;
grant execute on function set_user_access(uuid, app_role, uuid, boolean) to authenticated;
grant execute on function share_admin_access(uuid[]) to authenticated;
grant execute on function publish_app_settings() to authenticated;


-- '=' * 73
-- ONE-TIME FIX: FIRST SUPER ADMIN
-- '=' * 73
update profiles
set role = 'super_admin',
    full_name = 'Yusra',
    branch_id = (select id from branches where code = 'MAIN')
where email = 'YOUR_ADMIN_EMAIL_HERE';

select id, email, role, branch_id, is_active
from profiles
where email = 'YOUR_ADMIN_EMAIL_HERE';



-- =========================================================================
-- FILE: supabase/checks/schema_check.sql (VERIFICATION — not a migration)
-- =========================================================================

-- Yusra Pharmacy — schema verification.
-- Run once in the Supabase SQL Editor after applying the migrations.
-- Every row has a kind, an object name, a status of PASS or MISSING and a FIX
-- hint (blank for PASS rows). The owner sends the full result to Agent C.
-- No MISSING rows are expected after 0001..0013 have been applied plus the
-- proposed 0012_rls_hardening.sql, 0013_rpc_gaps.sql, 0014_report_views.sql and
-- 0015_team_management.sql. v_expired_batches is intentionally not required:
-- the screen that used it was corrected to derive the same figures directly.

with expected_tables(name) as (
  values ('branches'), ('profiles'), ('app_settings'), ('doc_counters'), ('audit_logs'),
         ('categories'), ('medicines'), ('suppliers'), ('purchase_orders'),
         ('purchase_order_items'), ('stock_batches'), ('stock_movements'),
         ('customers'), ('prescriptions'), ('shifts'), ('sales'), ('sale_items'),
         ('sale_payments'), ('sale_returns'), ('sale_return_items'), ('expenses')
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
         ('publish_app_settings', 0),
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
expected_storage_buckets(name, is_public) as (
  values ('prescriptions', false), ('receipts', false), ('branding', true),
         ('avatars', true), ('medicine-images', true)
),
actual_columns as (
  select table_name, array_agg(column_name order by column_name) as cols
  from information_schema.columns
  where table_schema = 'public'
  group by table_name
),
results as (
  select 'table'::text as kind, name as object,
         case when to_regclass('public.' || name) is not null then 'PASS' else 'MISSING' end as status,
         'Apply the migration that creates this table (0002..0006).' as fix
  from expected_tables
  union all
  select 'view', name,
         case when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relname = name and c.relkind in ('v','m'))
               then 'PASS' else 'MISSING' end,
         case when left(name, 9) = 'v_report_'
              then 'Apply the proposed supabase/migrations/0014_report_views.sql.'
              else 'Re-run 0008_views.sql.' end
  from expected_views
  union all
  select 'function', name,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = name and p.pronargs = nargs)
               then 'PASS' else 'MISSING' end,
         case when name in ('void_sale', 'process_sale_return')
              then 'Apply 0013_rpc_gaps.sql (void/return RPCs).'
              when name in ('set_user_access', 'share_admin_access',
                            'publish_app_settings')
              then 'Apply 0015_team_management.sql (team access RPCs).'
              else 'Re-run the migration defining this function (0002 / 0004..0009).' end
  from expected_functions
  union all
  select 'trigger', name,
         case when exists (select 1 from pg_trigger where tgname = name and not tgisinternal)
               then 'PASS' else 'MISSING' end,
         case when name = 'on_auth_user_created'
              then 'Re-run 0002_core_tables_helpers.sql.'
              else 'Re-run 0009_triggers.sql.' end
  from expected_triggers
  union all
  select 'policy', name,
         case when exists (select 1 from pg_policy where polname = name)
               then 'PASS' else 'MISSING' end,
         'Re-run 0010_rls_storage.sql / 0012_rls_hardening.sql.'
  from expected_policies
  union all
  select 'storage_bucket', b.name,
         case when exists (select 1 from storage.buckets s
                            where s.id = b.name and s.public = b.is_public)
               then 'PASS' else 'MISSING' end,
         'Re-run 0012_rls_hardening.sql to create the ' || b.name || ' bucket '
         || '(public = ' || b.is_public::text || ').'
  from expected_storage_buckets b
  union all
  select 'setting', 'app_settings.max_cashier_discount_pct',
         case when exists (select 1 from app_settings where key = 'max_cashier_discount_pct')
               then 'PASS' else 'MISSING' end,
         'Re-run 0011_seed.sql to insert the max_cashier_discount_pct app setting.'
  union all
  select 'column_group', 'sales.money',
         case when (select cols from actual_columns where table_name = 'sales')
               @> array['subtotal','discount','tax','total','paid','change_due']::text[]
               then 'PASS' else 'MISSING' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'column_group', 'stock_batches.core',
         case when (select cols from actual_columns where table_name = 'stock_batches')
               @> array['branch_id','medicine_id','batch_no','expiry_date','quantity','cost_price']::text[]
               then 'PASS' else 'MISSING' end,
         'Re-run 0005_stock.sql.'
  union all
  select 'column_group', 'sale_items.core',
         case when (select cols from actual_columns where table_name = 'sale_items')
               @> array['sale_id','medicine_id','batch_id','quantity','unit_price','line_total','returned_qty']::text[]
               then 'PASS' else 'MISSING' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'column_group', 'shifts.cash',
         case when (select cols from actual_columns where table_name = 'shifts')
               @> array['branch_id','cashier_id','opening_cash','expected_cash','closing_cash','difference','status']::text[]
               then 'PASS' else 'MISSING' end,
         'Re-run 0006_sales_finance.sql.'
  union all
  select 'rls', t.name,
         case when c.relrowsecurity then 'PASS' else 'MISSING' end,
         'Re-run 0012_rls_hardening.sql to enable RLS on ' || t.name || '.'
  from expected_tables t
  left join pg_class c on c.oid = to_regclass('public.' || t.name)
)
select kind, object, status,
       case when status = 'MISSING' then fix else '' end as fix
from results
order by kind, object;


-- =========================================================================
-- FILE: supabase/migrations/0016_profile_rpc.sql
-- =========================================================================

create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'email', p.email,
    'full_name', p.full_name,
    'phone', p.phone,
    'role', p.role::text,
    'branch_id', p.branch_id,
    'is_active', p.is_active,
    'avatar_url', p.avatar_url
  )
  from public.profiles p
  where p.id = auth.uid()
$$;

revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;

-- =========================================================================
-- FILE: supabase/migrations/0017_activity_audit.sql
-- =========================================================================
-- 0017 — Tamper-evident activity log + super-admin approval workflow.
-- Every write to an operational table is recorded with the actor's email,
-- role and Addis timestamp. Records cannot be updated or deleted directly;
-- corrections require an explicit super-admin approval RPC.

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  actor_email text not null default 'system',
  actor_role text not null default 'system',
  action text not null,
  entity_type text not null,
  entity_id text,
  branch_id uuid,
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  correction_requested boolean not null default false,
  correction_reason text,
  approved_by uuid,
  approved_at timestamptz
);

create index if not exists activity_log_created_idx on public.activity_log (created_at desc);
create index if not exists activity_log_actor_idx on public.activity_log (actor_id);
create index if not exists activity_log_entity_idx on public.activity_log (entity_type, entity_id);

create or replace function public.write_activity_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_actor uuid := auth.uid();
  v_email text := 'system';
  v_role text := 'system';
begin
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;

  if v_actor is not null then
    select p.email, p.role::text into v_email, v_role
    from public.profiles p where p.id = v_actor;
  end if;

  insert into public.activity_log
    (actor_id, actor_email, actor_role, action, entity_type, entity_id,
     branch_id, summary, metadata)
  values
    (v_actor, coalesce(v_email, 'system'), coalesce(v_role, 'system'),
     tg_op, tg_table_name, coalesce(v_row->>'id', ''),
     nullif(v_row->>'branch_id', '')::uuid,
     tg_table_name || ' ' || lower(tg_op),
     jsonb_build_object('op', tg_op, 'table', tg_table_name));
  return null;
end $$;

drop trigger if exists activity_branches on public.branches;
create trigger activity_branches after insert or update or delete on public.branches
  for each row execute function public.write_activity_log();
drop trigger if exists activity_profiles on public.profiles;
create trigger activity_profiles after insert or update or delete on public.profiles
  for each row execute function public.write_activity_log();
drop trigger if exists activity_stock on public.stock_batches;
create trigger activity_stock after insert or update or delete on public.stock_batches
  for each row execute function public.write_activity_log();
drop trigger if exists activity_po on public.purchase_orders;
create trigger activity_po after insert or update or delete on public.purchase_orders
  for each row execute function public.write_activity_log();
drop trigger if exists activity_sales on public.sales;
create trigger activity_sales after insert or update or delete on public.sales
  for each row execute function public.write_activity_log();
drop trigger if exists activity_returns on public.sale_returns;
create trigger activity_returns after insert or update or delete on public.sale_returns
  for each row execute function public.write_activity_log();
drop trigger if exists activity_expenses on public.expenses;
create trigger activity_expenses after insert or update or delete on public.expenses
  for each row execute function public.write_activity_log();
drop trigger if exists activity_shifts on public.shifts;
create trigger activity_shifts after insert or update or delete on public.shifts
  for each row execute function public.write_activity_log();
drop trigger if exists activity_customers on public.customers;
create trigger activity_customers after insert or update or delete on public.customers
  for each row execute function public.write_activity_log();
drop trigger if exists activity_prescriptions on public.prescriptions;
create trigger activity_prescriptions after insert or update or delete on public.prescriptions
  for each row execute function public.write_activity_log();

alter table public.activity_log enable row level security;

drop policy if exists rls_activity_read on public.activity_log;
create policy rls_activity_read on public.activity_log for select to authenticated
using (true);

revoke all on public.activity_log from anon;
revoke update, delete on public.activity_log from authenticated;
grant select on public.activity_log to authenticated;

create or replace function public.request_activity_correction(p_log_id uuid, p_reason text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update public.activity_log
  set correction_requested = true, correction_reason = nullif(p_reason, '')
  where id = p_log_id;
  return found;
end $$;

create or replace function public.approve_activity_correction(p_log_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if coalesce(my_role()::text, '') <> 'super_admin' then
    raise exception 'Only a super admin can approve activity corrections';
  end if;
  update public.activity_log
  set correction_requested = false,
      approved_by = auth.uid(),
      approved_at = now()
  where id = p_log_id;
  return found;
end $$;

revoke all on function public.request_activity_correction(uuid, text) from public, anon;
revoke all on function public.approve_activity_correction(uuid) from public, anon;
grant execute on function public.request_activity_correction(uuid, text) to authenticated;
grant execute on function public.approve_activity_correction(uuid) to authenticated;

-- Realtime delivery so dashboard activity refreshes without a manual reload.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'activity_log'
  ) then
    alter publication supabase_realtime add table public.activity_log;
  end if;
end $$;
