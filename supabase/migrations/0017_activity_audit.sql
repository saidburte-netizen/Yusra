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
