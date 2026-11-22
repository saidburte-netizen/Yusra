import { expect, test, type ViewportSize } from '@playwright/test';
import {
  BRANCH_A,
  NAV,
  RUN_ID,
  api,
  capture,
  choose,
  dbCount,
  dbRows,
  emailFor,
  field,
  futureDate,
  hasLabel,
  navigate,
  rowAction,
  sellViaPos,
  tap,
  unique,
  withRole,
  type DbRow,
} from '../fixtures/uat';

const MEDICINE_ID = process.env.UAT_NORMAL_MEDICINE_ID ?? '';
const MEDICINE_NAME = process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol';
const SUPPLIER_ID = process.env.UAT_SUPPLIER_ID ?? '';
const SUPPLIER_NAME = process.env.UAT_SUPPLIER_NAME ?? 'UAT Supplier';
const CASHIER_EMAIL = emailFor('cashier');
const month = (): string => new Date().toISOString().slice(0, 7);
const day = (): string => new Date().toISOString().slice(0, 10);

async function sumRows(rows: DbRow[], column: string): Promise<number> {
  return rows.reduce((total, row) => total + Number(row[column] ?? 0), 0);
}

async function medicineStock(): Promise<number> {
  const rows = await dbRows(
    'stock_batches',
    `branch_id=eq.${BRANCH_A}&medicine_id=eq.${MEDICINE_ID}&select=quantity`,
  );
  return sumRows(rows, 'quantity');
}

async function revenueTotal(): Promise<number> {
  const rows = await dbRows(
    'sales',
    `branch_id=eq.${BRANCH_A}&status=neq.voided&select=total`,
  );
  return sumRows(rows, 'total');
}

async function expenseTotal(): Promise<number> {
  const rows = await dbRows('expenses', `branch_id=eq.${BRANCH_A}&select=amount`);
  return sumRows(rows, 'amount');
}

/** Opens the cashier's shift through the UI only when one is not already open. */
async function ensureOpenShift(page: import('@playwright/test').Page): Promise<void> {
  const profile = await dbRows('profiles', `email=eq.${CASHIER_EMAIL}&select=id`);
  expect(profile.length, 'cross-role cashier profile must exist').toBe(1);
  const open = await dbRows(
    'shifts',
    `cashier_id=eq.${profile[0]?.id}&branch_id=eq.${BRANCH_A}&status=eq.open&select=id&limit=1`,
  );
  if (open.length) return;
  await navigate(page, NAV.shifts);
  await tap(page, 'Start shift');
  await (await field(page, 'Opening cash (ETB)')).fill('100');
  await tap(page, 'Start shift');
  expect(await hasLabel(page, 'Your open shift')).toBe(true);
}

test.describe('UAT — Cross-role chain', () => {
  test('XR-01 PO → stock → sale → finance → admin → correction with reconciled numbers', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    const batchNo = `XR${RUN_ID}`;
    const correctionReason = unique('XR correction reason');
    const expenseDescription = unique('XR Expense');
    const stockAtStart = await medicineStock();
    const revenueAtStart = await revenueTotal();
    const expensesAtStart = await expenseTotal();
    const salesAtStart = await dbCount('sales', `branch_id=eq.${BRANCH_A}`);
    const baselineNet = await dbRows(
      'v_report_net_profit',
      `branch_id=eq.${BRANCH_A}&period=eq.${month()}&select=revenue,expenses,net&limit=1`,
    );
    const netRevenueAtStart = Number(baselineNet[0]?.revenue ?? 0);
    const netExpensesAtStart = Number(baselineNet[0]?.expenses ?? 0);
    const baselineDaily = await dbRows(
      'v_report_sales_by_day',
      `branch_id=eq.${BRANCH_A}&date=eq.${day()}&select=net`,
    );
    const dailyAtStart = await sumRows(baselineDaily, 'net');
    let po: DbRow;
    let sale: DbRow;
    let expense: DbRow;

    await test.step('XR-01.1 store keeper receives a purchase order into stock', async () => {
      await withRole(browser, 'store_keeper', viewport, async (page) => {
        await navigate(page, NAV.purchasing);
        await tap(page, 'New purchase order');
        await choose(page, 'Supplier', SUPPLIER_NAME);
        await tap(page, 'Add line');
        await (await field(page, 'Search name or scan barcode')).fill(MEDICINE_NAME);
        await page.getByText(MEDICINE_NAME, { exact: true }).first().click();
        await (await field(page, 'Quantity')).last().fill('20');
        await (await field(page, 'Unit cost')).last().fill('2');
        await tap(page, 'Add');
        await tap(page, 'Create draft');
        const drafts = await dbRows(
          'purchase_orders',
          `status=eq.draft&supplier_id=eq.${SUPPLIER_ID}&order=created_at.desc&limit=1&select=id,po_no,status`,
        );
        expect(drafts.length, 'cross-role draft PO was not created').toBe(1);
        po = drafts[0];
        await capture(page, 'XR-01-po-draft');

        await navigate(page, NAV.purchasing);
        await page.getByText(String(po.po_no), { exact: true }).first().click();
        await tap(page, 'Approve & send');
        expect((await dbRows('purchase_orders', `id=eq.${po.id}&select=status`))[0]?.status).toBe('ordered');
        await tap(page, 'Receive goods');
        await (await field(page, 'Batch no')).fill(batchNo);
        await (await field(page, 'Expiry')).fill(futureDate());
        await tap(page, 'Receive goods');

        const received = await dbRows(
          'purchase_orders',
          `id=eq.${po.id}&select=status`,
        );
        expect(received[0]?.status).toBe('received');
        const batches = await dbRows(
          'stock_batches',
          `purchase_order_id=eq.${po.id}&batch_no=eq.${batchNo}&select=id,quantity`,
        );
        expect(batches.length).toBe(1);
        expect(Number(batches[0]?.quantity)).toBe(20);
        const movements = await dbRows(
          'stock_movements',
          `batch_id=eq.${batches[0]?.id}&movement_type=eq.purchase&select=quantity_change`,
        );
        expect(await sumRows(movements, 'quantity_change')).toBe(20);
        expect(await medicineStock(), 'received quantity must be on the shelves').toBe(stockAtStart + 20);
        await capture(page, 'XR-01-po-received');
      });
    });

    await test.step('XR-01.2 pharmacist sees the received stock', async () => {
      await withRole(browser, 'pharmacist', viewport, async (page) => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Batches');
        expect(await hasLabel(page, batchNo), 'received batch must be visible to the pharmacist').toBe(true);
        const batches = await dbRows(
          'stock_batches',
          `branch_id=eq.${BRANCH_A}&batch_no=eq.${batchNo}&select=id,quantity,medicine_id`,
        );
        expect(batches.length).toBe(1);
        expect(batches[0]?.medicine_id).toBe(MEDICINE_ID);
        expect(Number(batches[0]?.quantity)).toBe(20);
        await capture(page, 'XR-01-pharmacist-stock');
      });
    });

    await test.step('XR-01.3 cashier sells three units and the stock/revenue numbers agree', async () => {
      await withRole(browser, 'cashier', viewport, async (page) => {
        await ensureOpenShift(page);
        const beforeSale = await medicineStock();
        sale = await sellViaPos(page, MEDICINE_NAME, { quantity: 3 });
        const items = await dbRows(
          'sale_items',
          `sale_id=eq.${sale.id}&select=quantity,line_total,tax,unit_price`,
        );
        expect(await sumRows(items, 'quantity')).toBe(3);
        const gross = await sumRows(items, 'line_total');
        const tax = await sumRows(items, 'tax');
        expect(Number(sale.total), 'sale total must equal lines + VAT').toBeCloseTo(gross + tax, 2);
        expect(await medicineStock(), 'stock must fall by the sold quantity').toBe(beforeSale - 3);
        const saleMovements = await dbRows(
          'stock_movements',
          `reference_type=eq.sale&reference_id=eq.${sale.id}&select=quantity_change`,
        );
        expect(await sumRows(saleMovements, 'quantity_change')).toBe(-3);
        expect(await revenueTotal(), 'revenue delta must equal the sale total').toBeCloseTo(
          revenueAtStart + Number(sale.total),
          2,
        );
        await capture(page, 'XR-01-cashier-sale');
      });
    });

    await test.step('XR-01.4 accountant records an expense and the report views agree', async () => {
      await withRole(browser, 'accountant', viewport, async (page) => {
        await navigate(page, NAV.expenses);
        await tap(page, 'Add');
        await (await field(page, 'Amount')).fill('11.75');
        await choose(page, 'Category', 'Supplies');
        await choose(page, 'Payment method', 'Cash');
        await (await field(page, 'Description')).fill(expenseDescription);
        await tap(page, 'Save');
        const rows = await dbRows(
          'expenses',
          `description=eq.${encodeURIComponent(expenseDescription)}&select=id,amount,branch_id,expense_date`,
        );
        expect(rows.length).toBe(1);
        expense = rows[0];
        expect(Number(expense.amount)).toBe(11.75);
        expect(expense.branch_id).toBe(BRANCH_A);
        expect(String(expense.expense_date)).toContain(month());

        await navigate(page, NAV.reports);
        await tap(page, 'Net profit statement');
        expect(await hasLabel(page, 'Net profit statement')).toBe(true);
        await capture(page, 'XR-01-accountant-report');
        const net = await dbRows(
          'v_report_net_profit',
          `branch_id=eq.${BRANCH_A}&period=eq.${month()}&select=revenue,expenses,net&limit=1`,
        );
        expect(net.length, 'net profit view must have a row for this month').toBe(1);
        expect(Number(net[0]?.revenue) - netRevenueAtStart, 'view revenue delta must match the sale').toBeCloseTo(
          Number(sale.total),
          2,
        );
        expect(Number(net[0]?.expenses) - netExpensesAtStart, 'view expense delta must match the expense').toBeCloseTo(
          Number(expense.amount),
          2,
        );
        expect(Number(net[0]?.net)).toBeCloseTo(
          Number(net[0]?.revenue) - Number(net[0]?.expenses),
          2,
        );
        const daily = await dbRows(
          'v_report_sales_by_day',
          `branch_id=eq.${BRANCH_A}&date=eq.${day()}&select=net,invoices`,
        );
        expect(await sumRows(daily, 'net') - dailyAtStart).toBeCloseTo(Number(sale.total), 2);
      });
    });

    await test.step('XR-01.5 admin sees the sale on the dashboard and in the activity log', async () => {
      await withRole(browser, 'admin', viewport, async (page) => {
        await navigate(page, NAV.dashboard);
        expect(await hasLabel(page, "Today's sales")).toBe(true);
        expect(await dbCount('sales', `branch_id=eq.${BRANCH_A}`)).toBe(salesAtStart + 1);
        await capture(page, 'XR-01-admin-dashboard');

        await navigate(page, NAV.audit);
        expect(await hasLabel(page, CASHIER_EMAIL), 'the sale actor must appear in the audit trail').toBe(true);
        const activities = await dbRows(
          'activity_log',
          `entity_type=eq.sales&entity_id=eq.${sale.id}&select=id,actor_email`,
        );
        expect(activities.length).toBeGreaterThan(0);
        expect(activities[0]?.actor_email, 'cashier must be the recorded actor').toBe(CASHIER_EMAIL);
        await capture(page, 'XR-01-admin-activity');
      });
    });

    await test.step('XR-01.6 super admin approves the correction and all numbers reconcile', async () => {
      const created = await dbRows('profiles', `email=eq.${emailFor('super_admin')}&select=id`);
      expect(created.length).toBe(1);
      // Seed a fresh pending correction via PostgREST so the approval step is
      // repeatable even after the role specs have approved the bootstrap row.
      const pending = await api<DbRow[]>('activity_log', {
        method: 'POST',
        prefer: 'return=representation',
        body: {
          actor_id: created[0]?.id,
          actor_email: 'uat-cashier@yusra.test',
          actor_role: 'cashier',
          action: 'UPDATE',
          entity_type: 'sales',
          entity_id: String(sale.id),
          branch_id: BRANCH_A,
          summary: unique('XR correction summary'),
          correction_requested: true,
          correction_reason: correctionReason,
        },
      });
      expect(pending.status, pending.text).toBe(201);
      const logged = await dbRows(
        'activity_log',
        `entity_type=eq.purchase_orders&entity_id=eq.${po.id}&select=id`,
      );
      expect(logged.length, 'PO receipt must be audited').toBeGreaterThan(0);

      await withRole(browser, 'super_admin', viewport, async (page) => {
        await navigate(page, NAV.audit);
        await tap(page, 'Pending approval');
        await rowAction(page, correctionReason, 'Approve correction');
        const approved = await dbRows(
          'activity_log',
          `correction_reason=eq.${encodeURIComponent(correctionReason)}&select=correction_requested,approved_by,approved_at`,
        );
        expect(approved.length).toBe(1);
        expect(approved[0]?.correction_requested).toBe(false);
        expect(approved[0]?.approved_by).toBeTruthy();
        expect(approved[0]?.approved_at).toBeTruthy();

        // Final reconciliation: every role's view of the same chain.
        expect(await medicineStock()).toBe(stockAtStart + 20 - 3);
        expect(await revenueTotal() - revenueAtStart).toBeCloseTo(Number(sale.total), 2);
        expect(await expenseTotal() - expensesAtStart).toBeCloseTo(Number(expense.amount), 2);
        expect(Number(sale.total)).toBeGreaterThan(0);
        await capture(page, 'XR-01-super-admin-correction');
      });
    });
  });
});
