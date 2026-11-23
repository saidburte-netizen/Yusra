-- Expected/planned expenses for dashboard visibility (rent, utilities, other
-- recurring types managed by super admin). Salaries are derived from profiles.
create table if not exists public.expected_expenses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references public.branches(id) on delete cascade,
  name text not null,
  category text not null default 'Other',
  amount numeric(14,2) not null check (amount >= 0),
  due_day int not null default 1 check (due_day >= 1 and due_day <= 31),
  is_active boolean not null default true,
  notes text,
  created_by uuid references public.profiles(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists expected_expenses_branch_idx
  on public.expected_expenses (branch_id, is_active, due_day);

alter table public.expected_expenses enable row level security;

drop policy if exists rls_expected_expenses_read on public.expected_expenses;
create policy rls_expected_expenses_read on public.expected_expenses
for select to authenticated
using (
  branch_id is null
  or can_access_branch(branch_id)
);

drop policy if exists rls_expected_expenses_write on public.expected_expenses;
create policy rls_expected_expenses_write on public.expected_expenses
for all to authenticated
using (has_role('super_admin','admin'))
with check (has_role('super_admin','admin'));

grant select, insert, update, delete on public.expected_expenses to authenticated;
