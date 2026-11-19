create table stock_batches (
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
create index stock_batches_fefo_idx on stock_batches (branch_id, medicine_id, expiry_date) where quantity > 0;
create index stock_batches_expiry_idx on stock_batches (expiry_date) where quantity > 0;

create table stock_movements (
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
create index stock_movements_med_idx on stock_movements (medicine_id, created_at desc);
create index stock_movements_branch_idx on stock_movements (branch_id, created_at desc);