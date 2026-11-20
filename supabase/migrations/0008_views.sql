create or replace view v_stock_summary with (security_invoker = true) as
select
  b.id as branch_id,
  m.id as medicine_id,
  m.name,
  m.generic_name,
  m.sku,
  m.barcode,
  m.category_id,
  m.unit,
  m.reorder_level,
  m.selling_price,
  m.cost_price,
  m.is_active,
  coalesce(sum(sb.quantity) filter (where sb.expiry_date > current_date), 0)::int as available_qty,
  coalesce(sum(sb.quantity) filter (where sb.expiry_date <= current_date), 0)::int as expired_qty,
  min(sb.expiry_date) filter (where sb.quantity > 0 and sb.expiry_date > current_date) as nearest_expiry
from branches b
cross join medicines m
left join stock_batches sb
  on sb.branch_id = b.id and sb.medicine_id = m.id and sb.is_active
where b.is_active
group by b.id, m.id;

create or replace view v_low_stock with (security_invoker = true) as
select * from v_stock_summary
where is_active and available_qty <= reorder_level;

create or replace view v_expiring_batches with (security_invoker = true) as
select
  sb.id as batch_id,
  sb.branch_id,
  sb.medicine_id,
  m.name,
  sb.batch_no,
  sb.expiry_date,
  sb.quantity,
  (sb.expiry_date - current_date) as days_left,
  (sb.expiry_date <= current_date) as is_expired
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.quantity > 0 and sb.is_active
  and sb.expiry_date <= current_date + coalesce((select (value #>> '{}')::int from app_settings where key = 'expiry_alert_days'), 90);

create or replace view v_daily_sales with (security_invoker = true) as
select
  branch_id,
  (created_at at time zone 'Africa/Addis_Ababa')::date as sale_date,
  count(*)::int as invoices,
  sum(subtotal) as subtotal,
  sum(discount) as discount,
  sum(tax) as tax,
  sum(total) as total
from sales
where status <> 'voided'
group by branch_id, (created_at at time zone 'Africa/Addis_Ababa')::date;