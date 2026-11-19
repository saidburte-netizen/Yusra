create table customers (
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

create table prescriptions (
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
create index prescriptions_branch_idx on prescriptions (branch_id, status);

create table shifts (
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
create unique index one_open_shift_per_user on shifts (cashier_id) where status = 'open';
create index shifts_branch_idx on shifts (branch_id, opened_at desc);

create table sales (
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
create index sales_branch_idx on sales (branch_id, created_at desc);
create index sales_shift_idx on sales (shift_id);
create index sales_cashier_idx on sales (cashier_id, created_at desc);

create table sale_items (
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
create index sale_items_sale_idx on sale_items (sale_id);
create index sale_items_med_idx on sale_items (medicine_id);

create table sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  method payment_method not null,
  amount numeric(14,2) not null check (amount > 0),
  reference text
);
create index sale_payments_sale_idx on sale_payments (sale_id);

create table sale_returns (
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

create table sale_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references sale_returns(id) on delete cascade,
  sale_item_id uuid not null references sale_items(id),
  quantity int not null check (quantity > 0),
  amount numeric(14,2) not null default 0,
  restocked boolean not null default true
);

create table expenses (
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
create index expenses_branch_idx on expenses (branch_id, expense_date desc);