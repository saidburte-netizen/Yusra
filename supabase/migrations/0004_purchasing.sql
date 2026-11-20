create table purchase_orders (
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
create index po_branch_idx on purchase_orders (branch_id, created_at desc);
create index po_supplier_idx on purchase_orders (supplier_id);

create table purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  po_id uuid not null references purchase_orders(id) on delete cascade,
  medicine_id uuid not null references medicines(id),
  quantity_ordered int not null check (quantity_ordered > 0),
  quantity_received int not null default 0 check (quantity_received >= 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) generated always as (quantity_ordered * unit_cost) stored,
  unique (po_id, medicine_id)
);