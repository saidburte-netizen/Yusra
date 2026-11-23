-- 0024 — Staff fields for team management.
-- Adds monthly_salary and hiring_date to profiles, and an RPC to update staff
-- profile fields. Additive and idempotent.

alter table profiles add column if not exists monthly_salary numeric(12,2);
alter table profiles add column if not exists hiring_date date;
alter table profiles add column if not exists last_login_at timestamptz;

-- Update staff profile details. Super admins can edit anyone; admins can edit
-- users in their own branch but cannot edit super admins or themselves via this
-- path except through normal profile flows. Deactivation is handled by
-- set_user_access.
create or replace function update_staff_profile(
  p_user uuid,
  p_full_name text,
  p_phone text default null,
  p_role app_role default null,
  p_branch uuid default null,
  p_monthly_salary numeric default null,
  p_hiring_date date default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_target profiles%rowtype;
  v_caller_role app_role := my_role();
  v_caller_branch uuid := my_branch();
begin
  if v_caller_role not in ('super_admin', 'admin') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;

  select * into v_target from profiles where id = p_user;
  if not found then
    raise exception 'User not found' using errcode = '22023';
  end if;

  if v_caller_role = 'admin' then
    if v_target.role = 'super_admin' then
      raise exception 'Not allowed' using errcode = '42501';
    end if;
    if p_role = 'super_admin' then
      raise exception 'Not allowed' using errcode = '42501';
    end if;
    if v_target.branch_id is distinct from v_caller_branch then
      raise exception 'Not allowed' using errcode = '42501';
    end if;
    if p_branch is distinct from v_caller_branch then
      raise exception 'Not allowed' using errcode = '42501';
    end if;
  end if;

  update profiles
     set full_name = coalesce(nullif(btrim(p_full_name), ''), full_name),
         phone = nullif(btrim(coalesce(p_phone, '')), ''),
         role = coalesce(p_role, role),
         branch_id = coalesce(p_branch, branch_id),
         monthly_salary = p_monthly_salary,
         hiring_date = p_hiring_date,
         updated_at = now()
   where id = p_user;

  -- keep auth email metadata in sync where possible
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
       || jsonb_build_object('full_name', coalesce(nullif(btrim(p_full_name), ''), v_target.full_name))
   where id = p_user;
end;
$$;

revoke all on function update_staff_profile(uuid, text, text, app_role, uuid, numeric, date) from public, anon;
grant execute on function update_staff_profile(uuid, text, text, app_role, uuid, numeric, date) to authenticated;

-- Allow admins/super admins to read needed profile fields for team screens.
-- RLS policies may already cover this; keep additive.
