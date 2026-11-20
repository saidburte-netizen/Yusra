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
  update auth.users
     set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
           || jsonb_build_object(
                'role', p_role::text,
                'branch_id', coalesce(p_branch::text, ''))
   where id = p_user;

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
