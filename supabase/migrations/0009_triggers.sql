do $$
declare t text;
begin
  foreach t in array array['branches','profiles','categories','medicines','suppliers','purchase_orders','stock_batches','customers','prescriptions','sales','expenses','app_settings']
  loop
    execute format('create trigger trg_%s_updated before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

create or replace function trg_po_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.po_no is null or new.po_no = '' then
    new.po_no := next_doc_no('PO', new.branch_id);
  end if;
  return new;
end $$;
create trigger trg_po_numbering before insert on purchase_orders
  for each row execute function trg_po_defaults();

create or replace function trg_rx_defaults()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.rx_no is null or new.rx_no = '' then
    new.rx_no := next_doc_no('RX', new.branch_id);
  end if;
  return new;
end $$;
create trigger trg_rx_numbering before insert on prescriptions
  for each row execute function trg_rx_defaults();

create or replace function trg_po_total()
returns trigger language plpgsql as $$
begin
  new.total := new.subtotal + new.tax;
  return new;
end $$;
create trigger trg_po_total_calc before insert or update on purchase_orders
  for each row execute function trg_po_total();

create or replace function recalc_po_subtotal()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_po uuid := case when tg_op = 'DELETE' then old.po_id else new.po_id end;
begin
  update purchase_orders
  set subtotal = coalesce((select sum(line_total) from purchase_order_items where po_id = v_po), 0)
  where id = v_po;
  return null;
end $$;
create trigger trg_poi_recalc after insert or update or delete on purchase_order_items
  for each row execute function recalc_po_subtotal();

create or replace function guard_po_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status in ('received','partially_received')
       and coalesce(current_setting('app.via_rpc', true), '') <> '1' then
      raise exception 'Use goods receiving to receive stock';
    end if;
    if new.status in ('ordered','cancelled')
       and auth.uid() is not null and not has_role('super_admin','admin') then
      raise exception 'Only an admin can approve or cancel purchase orders';
    end if;
    if new.status = 'draft' and old.status <> 'draft' then
      raise exception 'An order cannot go back to draft';
    end if;
    if new.status = 'ordered' then
      new.approved_by := auth.uid();
      new.approved_at := now();
    end if;
  end if;
  return new;
end $$;
create trigger trg_po_guard before update on purchase_orders
  for each row execute function guard_po_status();

create or replace function protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if has_role('super_admin') then return new; end if;
  if old.id = auth.uid() then
    new.role := old.role;
    new.branch_id := old.branch_id;
    new.is_active := old.is_active;
    new.email := old.email;
  elsif has_role('admin') then
    if old.role = 'super_admin' or new.role = 'super_admin' then
      raise exception 'Admins cannot change super admin accounts';
    end if;
  else
    raise exception 'Not allowed';
  end if;
  return new;
end $$;
create trigger trg_profiles_protect before update on profiles
  for each row execute function protect_profile_fields();

create or replace function audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new); v_row := v_new;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_row := v_new;
    if v_old = v_new then return new; end if;
  else
    v_old := to_jsonb(old); v_row := v_old;
  end if;
  insert into audit_logs (user_id, action, table_name, record_id, branch_id, old_data, new_data)
  values (auth.uid(), tg_op, tg_table_name, coalesce(v_row->>'id', v_row->>'key'), nullif(v_row->>'branch_id', '')::uuid, v_old, v_new);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','branches','app_settings','categories','medicines','suppliers','purchase_orders','customers','prescriptions','shifts','sales','expenses']
  loop
    execute format('create trigger trg_%s_audit after insert or update or delete on %I for each row execute function audit_row()', t, t);
  end loop;
end $$;