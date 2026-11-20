create sequence medicine_sku_seq start 1;

create table categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table medicines (
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
create index medicines_name_trgm on medicines using gin (name extensions.gin_trgm_ops);
create index medicines_generic_trgm on medicines using gin (generic_name extensions.gin_trgm_ops);
create index medicines_category_idx on medicines (category_id);

create table suppliers (
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