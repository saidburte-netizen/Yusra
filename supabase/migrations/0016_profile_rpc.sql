-- 0016 — Read the signed-in user's profile through a SECURITY DEFINER RPC.
--
-- Direct PostgREST reads of public.profiles depend on RLS policies and table
-- grants. If either is missing, the app cannot read the role and falls back to
-- a fake cashier profile. This RPC bypasses RLS by design and returns only the
-- row for auth.uid(), so the role shown in the app is always the real stored
-- value. Safe to re-run.

create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'email', p.email,
    'full_name', p.full_name,
    'phone', p.phone,
    'role', p.role::text,
    'branch_id', p.branch_id,
    'is_active', p.is_active,
    'avatar_url', p.avatar_url
  )
  from public.profiles p
  where p.id = auth.uid()
$$;

revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
