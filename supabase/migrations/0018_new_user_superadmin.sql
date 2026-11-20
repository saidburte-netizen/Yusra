-- 0018 — Users created directly in Supabase (no role in app_metadata) are
-- super admins. The in-app Create user flow still supplies the selected role
-- in app_metadata, so staff accounts keep the role chosen by the admin.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role, branch_id)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_app_meta_data->>'role')::app_role, 'super_admin'),
    nullif(new.raw_app_meta_data->>'branch_id', '')::uuid
  );
  return new;
end $$;
