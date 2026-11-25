-- 0028 — live drug stock status and dismissible low-stock alerts.
-- Additive/idempotent. Apply after 0027.

-- Global threshold (default 5). Existing settings rows are left untouched.
insert into public.app_settings (key, value)
values ('low_stock_alert_threshold', to_jsonb(5))
on conflict (key) do nothing;

create table if not exists public.stock_alert_dismissals (
  medicine_id  uuid not null references public.medicines(id) on delete cascade,
  branch_id    uuid not null references public.branches(id) on delete cascade,
  dismissed_by uuid references public.profiles(id) on delete set null,
  dismissed_at timestamptz not null default now(),
  qty_at_dismiss integer not null default 0,
  primary key (medicine_id, branch_id)
);

alter table public.stock_alert_dismissals enable row level security;

drop policy if exists rls_stock_alert_dismissals_admin on public.stock_alert_dismissals;
create policy rls_stock_alert_dismissals_admin
on public.stock_alert_dismissals
for all to authenticated
using (has_role('super_admin', 'admin') and can_access_branch(branch_id))
with check (has_role('super_admin', 'admin') and can_access_branch(branch_id));

revoke all on table public.stock_alert_dismissals from anon;
grant select, insert, update, delete on table public.stock_alert_dismissals to authenticated;

-- Low/out rows with no live dismissal, or whose quantity has dropped again.
create or replace view public.v_low_stock_alerts with (security_invoker = true) as
select
  s.*,
  d.dismissed_by,
  d.dismissed_at,
  d.qty_at_dismiss
from public.v_stock_summary s
left join public.stock_alert_dismissals d
  on d.medicine_id = s.medicine_id and d.branch_id = s.branch_id
where s.is_active
  and s.available_qty < greatest(coalesce(nullif(
        (select value #>> '{}' from public.app_settings
          where key = 'low_stock_alert_threshold'), '')::int, 5), 0)
  and (d.medicine_id is null or s.available_qty < d.qty_at_dismiss)
  and can_access_branch(s.branch_id)
  and has_role('super_admin', 'admin');

revoke all on table public.v_low_stock_alerts from public, anon;
grant select on table public.v_low_stock_alerts to authenticated;

create or replace function public.dismiss_low_stock_alert(
  p_medicine uuid,
  p_branch uuid
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_qty int;
begin
  if not has_role('super_admin', 'admin') then
    raise exception 'Not allowed: admin access required' using errcode = '42501';
  end if;
  if not can_access_branch(p_branch) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;

  select available_qty into v_qty
  from public.v_low_stock_alerts
  where medicine_id = p_medicine and branch_id = p_branch;
  if not found then
    return false;
  end if;

  insert into public.stock_alert_dismissals
    (medicine_id, branch_id, dismissed_by, dismissed_at, qty_at_dismiss)
  values (p_medicine, p_branch, auth.uid(), now(), v_qty)
  on conflict (medicine_id, branch_id) do update
    set dismissed_by = excluded.dismissed_by,
        dismissed_at = excluded.dismissed_at,
        qty_at_dismiss = excluded.qty_at_dismiss;

  insert into public.activity_log
    (actor_id, actor_email, actor_role, action, entity_type, entity_id, branch_id, summary, metadata)
  values (
    auth.uid(),
    coalesce((select email from public.profiles where id = auth.uid()), 'system'),
    coalesce((select role::text from public.profiles where id = auth.uid()), 'system'),
    'dismiss_low_stock_alert', 'medicine', p_medicine::text, p_branch,
    'Dismissed low-stock alert',
    jsonb_build_object('qty_at_dismiss', v_qty)
  );
  return true;
end $$;

create or replace function public.dismiss_all_low_stock_alerts(p_branch uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_count int := 0;
begin
  if not has_role('super_admin', 'admin') then
    raise exception 'Not allowed: admin access required' using errcode = '42501';
  end if;
  if not can_access_branch(p_branch) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;

  with alerts as (
    insert into public.stock_alert_dismissals
      (medicine_id, branch_id, dismissed_by, dismissed_at, qty_at_dismiss)
    select medicine_id, branch_id, auth.uid(), now(), available_qty
    from public.v_low_stock_alerts
    where branch_id = p_branch
    on conflict (medicine_id, branch_id) do update
      set dismissed_by = excluded.dismissed_by,
          dismissed_at = excluded.dismissed_at,
          qty_at_dismiss = excluded.qty_at_dismiss
    returning 1
  )
  select count(*) into v_count from alerts;

  insert into public.activity_log
    (actor_id, actor_email, actor_role, action, entity_type, entity_id, branch_id, summary, metadata)
  values (
    auth.uid(),
    coalesce((select email from public.profiles where id = auth.uid()), 'system'),
    coalesce((select role::text from public.profiles where id = auth.uid()), 'system'),
    'dismiss_all_low_stock_alerts', 'branch', p_branch::text, p_branch,
    'Cleared all low-stock alerts',
    jsonb_build_object('cleared', v_count)
  );
  return v_count;
end $$;

-- Restock above the threshold removes the dismissal so the next drop alerts.
create or replace function public.clear_restocked_low_stock_alert()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_branch uuid;
  v_medicine uuid;
  v_threshold int;
  v_available int;
begin
  if tg_op = 'DELETE' then
    v_branch := old.branch_id;
    v_medicine := old.medicine_id;
  else
    v_branch := new.branch_id;
    v_medicine := new.medicine_id;
  end if;

  select greatest(coalesce(nullif(
        (select value #>> '{}' from public.app_settings
          where key = 'low_stock_alert_threshold'), '')::int, 5), 0)
    into v_threshold;
  select coalesce(sum(quantity) filter (where expiry_date > current_date), 0)::int
    into v_available
    from public.stock_batches
   where branch_id = v_branch and medicine_id = v_medicine and is_active;

  if v_available >= v_threshold then
    delete from public.stock_alert_dismissals
     where branch_id = v_branch and medicine_id = v_medicine;
  end if;
  return null;
end $$;

drop trigger if exists trg_stock_batches_clear_low_stock_alert on public.stock_batches;
create trigger trg_stock_batches_clear_low_stock_alert
  after insert or update or delete on public.stock_batches
  for each row execute function public.clear_restocked_low_stock_alert();

revoke all on function public.dismiss_low_stock_alert(uuid, uuid) from public, anon;
grant execute on function public.dismiss_low_stock_alert(uuid, uuid) to authenticated;
revoke all on function public.dismiss_all_low_stock_alerts(uuid) from public, anon;
grant execute on function public.dismiss_all_low_stock_alerts(uuid) to authenticated;
revoke all on function public.clear_restocked_low_stock_alert() from public, anon;
grant execute on function public.clear_restocked_low_stock_alert() to authenticated;
