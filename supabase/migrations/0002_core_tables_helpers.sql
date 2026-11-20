create table branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table profiles (
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
create index profiles_branch_idx on profiles(branch_id);

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
    coalesce((new.raw_app_meta_data->>'role')::app_role, 'super_admin'),
    nullif(new.raw_app_meta_data->>'branch_id', '')::uuid
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

create table app_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

create table doc_counters (
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

create table audit_logs (
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
create index audit_logs_created_idx on audit_logs (created_at desc);
create index audit_logs_record_idx on audit_logs (table_name, record_id);