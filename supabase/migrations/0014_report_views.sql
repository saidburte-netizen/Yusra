-- 0014 — Proposed reporting views (REVIEW BEFORE APPLYING).
--
-- The original 0001–0011 schema ships only four aggregate views. The Reports
-- screen in the app exposes twelve reports; this file defines them with the
-- exact column names the app already queries. Every view also exposes
-- `branch_id` — appended as the LAST column so an existing view can be
-- replaced with `create or replace view` — so a super_admin can filter a
-- report by branch. Other roles are still scoped by RLS. All views use
-- `security_invoker = true`, so the caller's policies apply and a cashier
-- never sees another branch's figures.
--
-- Apply once in the Supabase SQL Editor after reviewing the definitions.
-- It is additive and idempotent.

create or replace view v_report_sales_by_day with (security_invoker = true) as
select
  (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
  count(*)::int as invoices,
  coalesce(sum(s.subtotal), 0) as gross,
  coalesce(sum(s.discount), 0) as discounts,
  coalesce(sum(s.tax), 0) as vat,
  coalesce(sum(s.total), 0) as net,
  s.branch_id
from sales s
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_sales_by_cashier with (security_invoker = true) as
select
  coalesce(nullif(p.full_name, ''), s.cashier_id::text) as cashier,
  count(*)::int as invoices,
  coalesce(sum(s.total), 0) as total,
  s.branch_id
from sales s
left join profiles p on p.id = s.cashier_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_sales_payment with (security_invoker = true) as
select
  sp.method::text as payment_method,
  count(distinct sp.sale_id)::int as invoices,
  coalesce(sum(sp.amount), 0) as total,
  s.branch_id
from sale_payments sp
join sales s on s.id = sp.sale_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_sales_by_medicine with (security_invoker = true) as
select
  si.medicine_name as medicine,
  sum(si.quantity - si.returned_qty)::int as qty,
  coalesce(sum(si.line_total - si.discount_share), 0) as revenue,
  coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
  coalesce(sum(si.line_total - si.discount_share
    - si.cost_price * (si.quantity - si.returned_qty)), 0) as profit,
  s.branch_id
from sale_items si
join sales s on s.id = si.sale_id
where s.status <> 'voided'
group by 1, s.branch_id;

create or replace view v_report_profit with (security_invoker = true) as
with daily_revenue as (
  select
    (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
    coalesce(sum(s.total), 0) as revenue,
    s.branch_id
  from sales s
  where s.status <> 'voided'
  group by 1, s.branch_id
), daily_cost as (
  select
    (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
    coalesce(sum(si.cost_price * (si.quantity - si.returned_qty)), 0) as cost,
    s.branch_id
  from sale_items si
  join sales s on s.id = si.sale_id
  where s.status <> 'voided'
  group by 1, s.branch_id
)
select
  coalesce(r.date, c.date) as date,
  coalesce(r.revenue, 0) as revenue,
  coalesce(c.cost, 0) as cost,
  coalesce(r.revenue, 0) - coalesce(c.cost, 0) as profit,
  case when coalesce(r.revenue, 0) = 0 then 0
       else round(((coalesce(r.revenue, 0) - coalesce(c.cost, 0))
         / r.revenue * 100)::numeric, 2) end as margin,
  coalesce(r.branch_id, c.branch_id) as branch_id
from daily_revenue r
full join daily_cost c on c.date = r.date and c.branch_id = r.branch_id;

create or replace view v_report_stock_valuation with (security_invoker = true) as
select
  m.name as medicine,
  sum(sb.quantity)::int as qty,
  case when sum(sb.quantity) = 0 then 0
       else round(sum(sb.quantity * sb.cost_price) / sum(sb.quantity), 2) end as unit_cost,
  coalesce(sum(sb.quantity * sb.cost_price), 0) as value,
  sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0
group by m.id, m.name, sb.branch_id;

create or replace view v_report_expiry_losses with (security_invoker = true) as
select
  sb.expiry_date as expiry,
  m.name as medicine,
  sb.batch_no as batch,
  sb.quantity as qty,
  coalesce(sb.quantity * sb.cost_price, 0) as value,
  sb.branch_id
from stock_batches sb
join medicines m on m.id = sb.medicine_id
where sb.is_active and sb.quantity > 0 and sb.expiry_date <= current_date;

create or replace view v_report_purchases_supplier with (security_invoker = true) as
select
  s.name as supplier,
  count(*)::int as orders,
  coalesce(sum(po.total), 0) as total,
  po.branch_id
from purchase_orders po
join suppliers s on s.id = po.supplier_id
where po.status not in ('draft', 'cancelled')
group by s.id, s.name, po.branch_id;

create or replace view v_report_expenses with (security_invoker = true) as
select
  expense_date as date,
  category,
  coalesce(sum(amount), 0) as amount,
  branch_id
from expenses
group by expense_date, category, branch_id;

create or replace view v_report_net_profit with (security_invoker = true) as
with revenue as (
  select
    to_char((created_at at time zone 'Africa/Addis_Ababa'), 'YYYY-MM') as period,
    coalesce(sum(total), 0) as revenue,
    branch_id
  from sales
  where status <> 'voided'
  group by 1, branch_id
), costs as (
  select
    to_char(expense_date, 'YYYY-MM') as period,
    coalesce(sum(amount), 0) as expenses,
    branch_id
  from expenses
  group by 1, branch_id
)
select
  coalesce(r.period, c.period) as period,
  coalesce(r.revenue, 0) as revenue,
  coalesce(c.expenses, 0) as expenses,
  coalesce(r.revenue, 0) - coalesce(c.expenses, 0) as net,
  coalesce(r.branch_id, c.branch_id) as branch_id
from revenue r
full join costs c on c.period = r.period and c.branch_id = r.branch_id;

create or replace view v_report_shift_variance with (security_invoker = true) as
select
  coalesce(nullif(p.full_name, ''), sh.cashier_id::text) as cashier,
  to_char((sh.opened_at at time zone 'Africa/Addis_Ababa'), 'YYYY-MM-DD HH24:MI') as shift,
  coalesce(sh.expected_cash, 0) as expected,
  coalesce(sh.closing_cash, 0) as actual,
  coalesce(sh.closing_cash, 0) - coalesce(sh.expected_cash, 0) as variance,
  sh.branch_id
from shifts sh
left join profiles p on p.id = sh.cashier_id
where sh.status = 'closed';

create or replace view v_report_controlled_register with (security_invoker = true) as
select
  (s.created_at at time zone 'Africa/Addis_Ababa')::date as date,
  si.medicine_name as medicine,
  sum(si.quantity - si.returned_qty)::int as qty,
  coalesce(rx.prescriber_name, '') as prescriber,
  coalesce(rx.patient_name, '') as patient,
  s.branch_id
from sale_items si
join sales s on s.id = si.sale_id
join medicines m on m.id = si.medicine_id
left join prescriptions rx on rx.id = s.prescription_id
where s.status <> 'voided' and m.is_controlled
group by 1, 2, 4, 5, s.branch_id;

-- Reports are readable by signed-in staff only; anon must never see figures.
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
