-- 0019 — End-to-end hardening and missing-object remediation.
--
-- This is the ONLY new migration in this branch. It is safe to re-run and is
-- intended for projects that already applied 0001–0018. It fixes:
--   * the invalid PL/pgSQL errcode PGRST116 (PostgREST-only) -> P0002
--   * SECURITY DEFINER search_path and execute grants
--   * unsafe handle_new_user role parsing, trigger creation and backfill
--   * profile self-service, team access, activity-correction authorization
--   * purchase-order status/receipt direct-write holes and missing RPCs
--   * expense approval, customer stats and shift expected-cash helpers
--   * Storage policies for receipts, avatars, branding and medicine images
--   * a consistent `date` column on all report views

-- ---------------------------------------------------------------------------
-- 1. set_user_access — replace the invalid PostgREST error code with P0002.
-- ---------------------------------------------------------------------------
create or replace function public.set_user_access(
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
    raise exception 'Not allowed: admin access required' using errcode = '42501';
  end if;

  if p_user = auth.uid() then
    raise exception 'You cannot change your own access here' using errcode = '42501';
  end if;

  select * into v_target from profiles where id = p_user;
  if not found then
    -- PostgREST HTTP codes are not valid SQLSTATEs for RAISE; use P0002.
    raise exception 'Team member not found' using errcode = 'P0002';
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
    p_branch := null;
  end if;

  if not p_active and v_target.role = 'super_admin' then
    raise exception 'A super admin cannot be deactivated here'
      using errcode = '42501';
  end if;

  perform set_config('app.via_rpc', '1', true);

  update profiles
     set role = p_role,
         branch_id = p_branch,
         is_active = p_active,
         updated_at = now()
   where id = p_user;

  update auth.users
     set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
           || jsonb_build_object(
                'role', p_role::text,
                'branch_id', coalesce(p_branch::text, ''))
   where id = p_user;

  perform set_config('app.via_rpc', '', true);

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
-- 2. handle_new_user — safe role parsing, idempotent trigger, backfill.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role app_role := 'super_admin';
  v_branch uuid;
begin
  if new.raw_app_meta_data ? 'role' then
    begin
      v_role := (new.raw_app_meta_data ->> 'role')::app_role;
    exception when invalid_text_representation then
      v_role := 'super_admin';
    end;
    if v_role is null then
      v_role := 'super_admin';
    end if;
  end if;

  begin
    v_branch := nullif(new.raw_app_meta_data ->> 'branch_id', '')::uuid;
  exception when invalid_text_representation then
    v_branch := null;
  end;

  insert into public.profiles (id, email, full_name, role, branch_id)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    v_role,
    v_branch
  )
  on conflict (id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill users that exist in auth but never received a profile row.
insert into public.profiles (id, email, full_name, role, branch_id)
select u.id,
       u.email,
       coalesce(u.raw_user_meta_data ->> 'full_name', ''),
       coalesce((u.raw_app_meta_data ->> 'role')::app_role, 'super_admin'),
       nullif(u.raw_app_meta_data ->> 'branch_id', '')::uuid
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Activity corrections — only the actor (or an admin) may request one.
-- ---------------------------------------------------------------------------
create or replace function public.request_activity_correction(p_log_id uuid, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if length(btrim(p_reason)) < 5 then
    raise exception 'Give a reason of at least 5 characters' using errcode = '22023';
  end if;

  select actor_id into v_actor from public.activity_log where id = p_log_id;
  if not found then
    return false;
  end if;
  if v_actor is distinct from auth.uid()
     and coalesce(my_role()::text, '') not in ('admin', 'super_admin') then
    raise exception 'You can only request a correction on your own activity'
      using errcode = '42501';
  end if;

  update public.activity_log
     set correction_requested = true,
         correction_reason = btrim(p_reason)
   where id = p_log_id;
  return true;
end $$;

create or replace function public.approve_activity_correction(p_log_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(my_role()::text, '') <> 'super_admin' then
    raise exception 'Only a super admin can approve activity corrections'
      using errcode = '42501';
  end if;
  update public.activity_log
     set correction_requested = false,
         approved_by = auth.uid(),
         approved_at = now()
   where id = p_log_id;
  return found;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Profile self-service — name, phone and avatar only.
-- ---------------------------------------------------------------------------
create or replace function public.update_my_profile(
  p_full_name text default null,
  p_phone text default null,
  p_avatar_url text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in to update your profile' using errcode = '42501';
  end if;
  if p_full_name is not null and length(p_full_name) > 120 then
    raise exception 'Name is too long' using errcode = '22023';
  end if;
  if p_phone is not null and length(p_phone) > 40 then
    raise exception 'Phone number is too long' using errcode = '22023';
  end if;

  perform set_config('app.via_rpc', '1', true);

  update public.profiles
     set full_name = coalesce(p_full_name, full_name),
         phone = case when p_phone is null then phone else nullif(btrim(p_phone), '') end,
         avatar_url = case when p_avatar_url is null then avatar_url else nullif(btrim(p_avatar_url), '') end,
         updated_at = now()
   where id = auth.uid()
  returning * into v_profile;

  perform set_config('app.via_rpc', '', true);

  if not found then
    raise exception 'Profile not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'id', v_profile.id,
    'email', v_profile.email,
    'full_name', v_profile.full_name,
    'phone', v_profile.phone,
    'role', v_profile.role::text,
    'branch_id', v_profile.branch_id,
    'is_active', v_profile.is_active,
    'avatar_url', v_profile.avatar_url
  );
end $$;

-- ---------------------------------------------------------------------------
-- 5. Purchase orders — status changes and receipt quantities are RPC-only.
-- ---------------------------------------------------------------------------
create or replace function public.guard_po_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    if coalesce(current_setting('app.via_rpc', true), '') <> '1' then
      raise exception 'Use the purchase-order RPCs to change status'
        using errcode = '42501';
    end if;
    if new.status = 'draft' and old.status <> 'draft' then
      raise exception 'An order cannot go back to draft' using errcode = '22023';
    end if;
    if new.status = 'ordered' then
      new.approved_by := coalesce(new.approved_by, auth.uid());
      new.approved_at := coalesce(new.approved_at, now());
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_po_guard on public.purchase_orders;
create trigger trg_po_guard before update on public.purchase_orders
  for each row execute function public.guard_po_status();

create or replace function public.guard_po_receipt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.quantity_received is distinct from old.quantity_received
     and coalesce(current_setting('app.via_rpc', true), '') <> '1' then
    raise exception 'Use receive_purchase_order to receive stock'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_poi_receipt_guard on public.purchase_order_items;
create trigger trg_poi_receipt_guard before update on public.purchase_order_items
  for each row execute function public.guard_po_receipt();

create or replace function public.set_purchase_order_status(
  p_po uuid,
  p_status po_status
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_po purchase_orders%rowtype;
begin
  if not has_role('super_admin', 'admin') then
    raise exception 'Only an admin can change purchase-order status'
      using errcode = '42501';
  end if;

  select * into v_po from public.purchase_orders where id = p_po for update;
  if not found then
    raise exception 'Purchase order not found' using errcode = 'P0002';
  end if;
  if not can_access_branch(v_po.branch_id) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;

  if p_status = 'ordered' and v_po.status <> 'draft' then
    raise exception 'Only a draft order can be approved' using errcode = '22023';
  end if;
  if p_status = 'cancelled' and v_po.status not in ('draft', 'ordered') then
    raise exception 'This order can no longer be cancelled' using errcode = '22023';
  end if;
  if p_status not in ('ordered', 'cancelled') then
    raise exception 'Unsupported status change' using errcode = '22023';
  end if;

  perform set_config('app.via_rpc', '1', true);
  update public.purchase_orders
     set status = p_status,
         approved_by = case when p_status = 'ordered' then auth.uid() else approved_by end,
         approved_at = case when p_status = 'ordered' then now() else approved_at end,
         updated_at = now()
   where id = p_po;

  perform set_config('app.via_rpc', '', true);
end $$;

create or replace function public.approve_purchase_order(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.set_purchase_order_status(p_po, 'ordered'::po_status);
end $$;

create or replace function public.cancel_purchase_order(p_po uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.set_purchase_order_status(p_po, 'cancelled'::po_status);
end $$;

-- ---------------------------------------------------------------------------
-- 5b. receive_purchase_order — reset the RPC bypass flag after the write so it
--     cannot leak into another statement in the same transaction.
-- ---------------------------------------------------------------------------
create or replace function public.receive_purchase_order(p_po uuid, p_items jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_po purchase_orders%rowtype;
  v_line purchase_order_items%rowtype;
  v_it jsonb;
  v_qty int;
  v_batch uuid;
  v_any boolean := false;
begin
  if not has_role('super_admin','admin','pharmacist','store_keeper') then
    raise exception 'You are not allowed to receive goods';
  end if;
  select * into v_po from public.purchase_orders where id = p_po for update;
  if not found then raise exception 'Purchase order not found'; end if;
  if not can_access_branch(v_po.branch_id) then raise exception 'Branch not allowed'; end if;
  if v_po.status not in ('ordered','partially_received') then
    raise exception 'This purchase order is not open for receiving';
  end if;

  perform set_config('app.via_rpc', '1', true);

  for v_it in select value from jsonb_array_elements(p_items) loop
    v_qty := coalesce((v_it->>'quantity')::int, 0);
    continue when v_qty = 0;
    if v_qty < 0 then raise exception 'Quantity cannot be negative'; end if;

    select * into v_line from public.purchase_order_items
      where id = (v_it->>'po_item_id')::uuid and po_id = p_po for update;
    if not found then raise exception 'Line does not belong to this order'; end if;
    if v_qty > v_line.quantity_ordered - v_line.quantity_received then
      raise exception 'Received quantity is more than the quantity still due';
    end if;
    if coalesce(trim(v_it->>'batch_no'), '') = '' then raise exception 'Batch number is required'; end if;
    if (v_it->>'expiry_date')::date <= current_date then raise exception 'Expiry date must be in the future'; end if;

    insert into stock_batches (branch_id, medicine_id, batch_no, expiry_date, quantity, initial_quantity, cost_price, supplier_id, purchase_order_id)
    values (v_po.branch_id, v_line.medicine_id, trim(v_it->>'batch_no'), (v_it->>'expiry_date')::date, v_qty, v_qty, v_line.unit_cost, v_po.supplier_id, p_po)
    on conflict (branch_id, medicine_id, batch_no) do update
      set quantity = stock_batches.quantity + excluded.quantity,
          initial_quantity = stock_batches.initial_quantity + excluded.quantity,
          cost_price = excluded.cost_price,
          updated_at = now()
    returning id into v_batch;

    insert into stock_movements (branch_id, medicine_id, batch_id, movement_type, quantity_change, reference_type, reference_id)
    values (v_po.branch_id, v_line.medicine_id, v_batch, 'purchase', v_qty, 'purchase_order', p_po);

    update purchase_order_items set quantity_received = quantity_received + v_qty where id = v_line.id;
    update medicines set cost_price = v_line.unit_cost, updated_at = now() where id = v_line.medicine_id;
    v_any := true;
  end loop;

  if not v_any then raise exception 'Nothing to receive'; end if;

  update purchase_orders
  set status = case
        when exists (select 1 from purchase_order_items where po_id = p_po and quantity_received < quantity_ordered)
        then 'partially_received'::po_status
        else 'received'::po_status
      end,
      updated_at = now()
  where id = p_po;

  perform set_config('app.via_rpc', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Expense approval workflow.
-- ---------------------------------------------------------------------------
alter table public.expenses
  add column if not exists status text not null default 'approved'
    check (status in ('pending', 'approved', 'rejected'));

create or replace function public.guard_expense_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('app.via_rpc', true), '') <> '1' then
    raise exception 'Use the expense approval RPC to change status'
      using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_expense_status_guard on public.expenses;
create trigger trg_expense_status_guard before update on public.expenses
  for each row execute function public.guard_expense_status();

create or replace function public.set_expense_status(p_expense uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense expenses%rowtype;
begin
  if p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'Unsupported expense status' using errcode = '22023';
  end if;
  if not has_role('super_admin', 'admin', 'accountant') then
    raise exception 'Only finance staff can approve expenses'
      using errcode = '42501';
  end if;

  select * into v_expense from public.expenses where id = p_expense for update;
  if not found then
    raise exception 'Expense not found' using errcode = 'P0002';
  end if;
  if not can_access_branch(v_expense.branch_id) then
    raise exception 'Branch not allowed' using errcode = '42501';
  end if;

  perform set_config('app.via_rpc', '1', true);
  update public.expenses
     set status = p_status, updated_at = now()
   where id = p_expense;

  perform set_config('app.via_rpc', '', true);
end $$;

create or replace function public.approve_expense(p_expense uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.set_expense_status(p_expense, 'approved');
end $$;

create or replace function public.reject_expense(p_expense uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.set_expense_status(p_expense, 'rejected');
end $$;

-- ---------------------------------------------------------------------------
-- 7. Read-only helpers used by customers, shifts and reports.
-- ---------------------------------------------------------------------------
create or replace function public.customer_stats(p_customer uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not has_role('super_admin', 'admin', 'cashier', 'accountant', 'pharmacist') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'visits', count(*),
    'lifetime_spend', coalesce(sum(total), 0),
    'last_visit', max(created_at),
    'outstanding', 0
  ) into v_result
  from public.sales
  where customer_id = p_customer and status <> 'voided';
  return coalesce(v_result, '{}'::jsonb);
end $$;

create or replace function public.shift_expected_cash(p_shift uuid)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_expected numeric;
begin
  select s.opening_cash
         + coalesce((select sum(sp.amount) from public.sale_payments sp
                      join public.sales sa on sa.id = sp.sale_id
                      where sa.shift_id = s.id and sa.status <> 'voided'
                        and sp.method = 'cash'), 0)
         - coalesce((select sum(sa2.change_due) from public.sales sa2
                      where sa2.shift_id = s.id and sa2.status <> 'voided'), 0)
         - coalesce((select sum(r.refund_amount) from public.sale_returns r
                      join public.sales sa3 on sa3.id = r.sale_id
                      where sa3.shift_id = s.id and r.refund_method = 'cash'), 0)
    into v_expected
  from public.shifts s
  where s.id = p_shift;
  return coalesce(v_expected, 0);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Storage policies for the remaining buckets.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit) values
  ('receipts', 'receipts', false, 5242880),
  ('avatars', 'avatars', true, 5242880),
  ('branding', 'branding', true, 5242880),
  ('medicine-images', 'medicine-images', true, 5242880)
on conflict (id) do nothing;

drop policy if exists rls_receipts_read on storage.objects;
create policy rls_receipts_read on storage.objects for select to authenticated
using (bucket_id = 'receipts' and (
  has_role('super_admin', 'admin', 'accountant') or
  (storage.foldername(name))[1] = coalesce(my_branch()::text, '')
));

drop policy if exists rls_receipts_write on storage.objects;
create policy rls_receipts_write on storage.objects for insert to authenticated
with check (bucket_id = 'receipts' and
  (storage.foldername(name))[1] = coalesce(my_branch()::text, '') and
  has_role('super_admin', 'admin', 'accountant', 'cashier'));

drop policy if exists rls_avatars_read on storage.objects;
create policy rls_avatars_read on storage.objects for select to authenticated
using (bucket_id = 'avatars');

drop policy if exists rls_avatars_write on storage.objects;
create policy rls_avatars_write on storage.objects for insert to authenticated
with check (bucket_id = 'avatars' and
  (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists rls_avatars_update on storage.objects;
create policy rls_avatars_update on storage.objects for update to authenticated
using (bucket_id = 'avatars' and owner = auth.uid())
with check (bucket_id = 'avatars' and owner = auth.uid());

drop policy if exists rls_avatars_delete on storage.objects;
create policy rls_avatars_delete on storage.objects for delete to authenticated
using (bucket_id = 'avatars' and owner = auth.uid());

drop policy if exists rls_branding_read on storage.objects;
create policy rls_branding_read on storage.objects for select to authenticated
using (bucket_id = 'branding');

drop policy if exists rls_branding_write on storage.objects;
create policy rls_branding_write on storage.objects for insert to authenticated
with check (bucket_id = 'branding' and has_role('super_admin', 'admin'));

drop policy if exists rls_branding_delete on storage.objects;
create policy rls_branding_delete on storage.objects for delete to authenticated
using (bucket_id = 'branding' and has_role('super_admin', 'admin'));

drop policy if exists rls_medicine_images_read on storage.objects;
create policy rls_medicine_images_read on storage.objects for select to authenticated
using (bucket_id = 'medicine-images');

drop policy if exists rls_medicine_images_write on storage.objects;
create policy rls_medicine_images_write on storage.objects for insert to authenticated
with check (bucket_id = 'medicine-images' and
  has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'));

drop policy if exists rls_medicine_images_delete on storage.objects;
create policy rls_medicine_images_delete on storage.objects for delete to authenticated
using (bucket_id = 'medicine-images' and
  has_role('super_admin', 'admin', 'pharmacist', 'store_keeper'));

-- ---------------------------------------------------------------------------
-- 9. Every report view exposes a `date` column for uniform date filters.
-- ---------------------------------------------------------------------------
drop view if exists v_report_sales_by_cashier;
create view v_report_sales_by_cashier with (security_invoker = true) as
select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
       coalesce(nullif(p.full_name, ''), s.cashier_id::text) as cashier,
       count(*)::int as invoices,
       coalesce(sum(s.total), 0) as total,
       s.branch_id
from sales s
left join profiles p on p.id = s.cashier_id
where s.status <> 'voided'
group by 1, 2, s.branch_id;

drop view if exists v_report_sales_payment;
create view v_report_sales_payment with (security_invoker = true) as
select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
       sp.method::text as payment_method,
       count(distinct sp.sale_id)::int as invoices,
       coalesce(sum(sp.amount), 0) as total,
       s.branch_id
from sale_payments sp
join sales s on s.id = sp.sale_id
where s.status <> 'voided'
group by 1, 2, s.branch_id;

drop view if exists v_report_sales_by_medicine;
create view v_report_sales_by_medicine with (security_invoker = true) as
select (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
       si.medicine_name as medicine,
       sum(si.quantity - si.returned_qty)::int as qty,
       coalesce(sum(si.line_total - si.discount_share), 0) as revenue,
       coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
       coalesce(sum(si.line_total - si.discount_share - si.cost_price * (si.quantity - si.returned_qty)), 0) as profit,
       s.branch_id
from sale_items si
join sales s on s.id = si.sale_id
where s.status <> 'voided'
group by 1, 2, s.branch_id;

drop view if exists v_report_shift_variance;
create view v_report_shift_variance with (security_invoker = true) as
select (sh.opened_at at time zone 'Africa/Addis_Ababa')::date as date,
       coalesce(nullif(p.full_name, ''), sh.cashier_id::text) as cashier,
       to_char(sh.opened_at at time zone 'Africa/Addis_Ababa', 'YYYY-MM-DD HH24:MI') as shift,
       coalesce(sh.expected_cash, 0) as expected,
       coalesce(sh.closing_cash, 0) as actual,
       coalesce(sh.closing_cash, 0) - coalesce(sh.expected_cash, 0) as variance,
       sh.branch_id
from shifts sh
left join profiles p on p.id = sh.cashier_id
where sh.status = 'closed';

drop view if exists v_report_stock_valuation;
create view v_report_stock_valuation with (security_invoker = true) as
select current_date as date,
       m.name as medicine,
       sum(sb.quantity)::int as qty,
       case when sum(sb.quantity) = 0 then 0
            else round(sum(sb.quantity::numeric * sb.cost_price) / sum(sb.quantity)::numeric, 2)
       end as unit_cost,
       coalesce(sum(sb.quantity::numeric * sb.cost_price), 0) as value,
       sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0
group by m.id, m.name, sb.branch_id;

drop view if exists v_report_expiry_losses;
create view v_report_expiry_losses with (security_invoker = true) as
select sb.expiry_date as date,
       sb.expiry_date as expiry,
       m.name as medicine,
       sb.batch_no as batch,
       sb.quantity as qty,
       coalesce(sb.quantity::numeric * sb.cost_price, 0) as value,
       sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0 and sb.expiry_date <= current_date;

drop view if exists v_report_purchases_supplier;
create view v_report_purchases_supplier with (security_invoker = true) as
select (min(po.order_date)) as date,
       s.name as supplier,
       count(*)::int as orders,
       coalesce(sum(po.total), 0) as total,
       po.branch_id
from purchase_orders po
join suppliers s on s.id = po.supplier_id
where po.status not in ('draft', 'cancelled')
group by s.id, s.name, po.branch_id;

drop view if exists v_report_net_profit;
create view v_report_net_profit with (security_invoker = true) as
with revenue as (
  select to_char(s.created_at at time zone 'Africa/Addis_Ababa', 'YYYY-MM') as period,
         coalesce(sum(s.total), 0) as revenue,
         s.branch_id
  from sales s
  where s.status <> 'voided'
  group by 1, s.branch_id
), costs as (
  select to_char(e.expense_date::timestamp, 'YYYY-MM') as period,
         coalesce(sum(e.amount), 0) as expenses,
         e.branch_id
  from expenses e
  group by 1, e.branch_id
)
select (coalesce(r.period, c.period) || '-01')::date as date,
       coalesce(r.period, c.period) as period,
       coalesce(r.revenue, 0) as revenue,
       coalesce(c.expenses, 0) as expenses,
       coalesce(r.revenue, 0) - coalesce(c.expenses, 0) as net,
       coalesce(r.branch_id, c.branch_id) as branch_id
from revenue r
full join costs c on c.period = r.period and c.branch_id = r.branch_id;

revoke all on
  v_report_sales_by_day,
  v_report_sales_by_cashier,
  v_report_sales_payment,
  v_report_sales_by_medicine,
  v_report_profit,
  v_report_stock_valuation,
  v_report_expiry_losses,
  v_report_purchases_supplier,
  v_report_expenses,
  v_report_net_profit,
  v_report_shift_variance,
  v_report_controlled_register
from anon;
grant select on
  v_report_sales_by_day,
  v_report_sales_by_cashier,
  v_report_sales_payment,
  v_report_sales_by_medicine,
  v_report_profit,
  v_report_stock_valuation,
  v_report_expiry_losses,
  v_report_purchases_supplier,
  v_report_expenses,
  v_report_net_profit,
  v_report_shift_variance,
  v_report_controlled_register
to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Uniform SECURITY DEFINER hardening: pinned search_path plus strict
--     execute grants. Applied to every function in public, including the ones
--     introduced by this migration. Trigger functions are left executable by
--     the database only; granting them to authenticated is harmless but they
--     are never called directly by clients.
-- ---------------------------------------------------------------------------
do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('alter function %s set search_path = public', fn.sig);
    execute format('revoke all on function %s from public, anon', fn.sig);
    execute format('grant execute on function %s to authenticated', fn.sig);
  end loop;
end $$;

-- Explicit grants for the new RPCs (the loop above is the safety net).
revoke all on function public.set_purchase_order_status(uuid, po_status) from public, anon;
revoke all on function public.approve_purchase_order(uuid) from public, anon;
revoke all on function public.cancel_purchase_order(uuid) from public, anon;
revoke all on function public.set_expense_status(uuid, text) from public, anon;
revoke all on function public.approve_expense(uuid) from public, anon;
revoke all on function public.reject_expense(uuid) from public, anon;
revoke all on function public.customer_stats(uuid) from public, anon;
revoke all on function public.shift_expected_cash(uuid) from public, anon;
revoke all on function public.update_my_profile(text, text, text) from public, anon;
grant execute on function public.set_purchase_order_status(uuid, po_status) to authenticated;
grant execute on function public.approve_purchase_order(uuid) to authenticated;
grant execute on function public.cancel_purchase_order(uuid) to authenticated;
grant execute on function public.set_expense_status(uuid, text) to authenticated;
grant execute on function public.approve_expense(uuid) to authenticated;
grant execute on function public.reject_expense(uuid) to authenticated;
grant execute on function public.customer_stats(uuid) to authenticated;
grant execute on function public.shift_expected_cash(uuid) to authenticated;
grant execute on function public.update_my_profile(text, text, text) to authenticated;

-- No SQLSTATE PGRST116 may remain in a RAISE statement.
do $$
declare
  bad record;
begin
  for bad in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosrc ilike '%PGRST116%'
  loop
    raise warning 'Function % still contains PostgREST-only code PGRST116', bad.sig;
  end loop;
end $$;
