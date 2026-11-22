import { expect, test, type ViewportSize } from '@playwright/test';
import {
  NAV,
  RUN_ID,
  assertAccessDenied,
  assertNoLabel,
  button,
  capture,
  dbCount,
  dbRows,
  discountField,
  field,
  hasButtonMatching,
  hasLabel,
  navigate,
  pageToken,
  seedStock,
  tap,
  tapMatching,
  unique,
  userToken,
  walkNav,
  withRole,
} from '../fixtures/uat';

const NORMAL_NAME = process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol';
const RX_NAME = process.env.UAT_RX_MEDICINE_NAME ?? 'UAT Amoxicillin';

test.describe('UAT — Cashier', () => {
  test('CA-01 sign in, nav walk, hidden and direct-URL forbidden areas', async ({ browser }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'cashier', viewport, async (page) => {
      await test.step('CA-01.1 POS landing and every permitted nav item', async () => {
        await expect(page).toHaveURL(/\/pos$/);
        expect(await hasLabel(page, NAV.pos)).toBe(true);
        await walkNav(page, 'cashier');
      });

      await test.step('CA-01.2 no Needs ordering and no branch switcher', async () => {
        await navigate(page, NAV.inventory);
        await assertNoLabel(page, 'Needs ordering');
        await assertNoLabel(page, 'All branches (view only)');
        await assertNoLabel(page, 'Manage branches');
        await capture(page, 'CA-01-inventory-no-needs-ordering');
      });

      await test.step('CA-01.3 forbidden nav items are hidden', async () => {
        for (const label of [
          NAV.purchasing,
          NAV.suppliers,
          NAV.expenses,
          NAV.reports,
          NAV.users,
          NAV.team,
          NAV.branches,
          NAV.settings,
          NAV.audit,
        ]) {
          await assertNoLabel(page, label);
        }
        await capture(page, 'CA-01-forbidden-nav-hidden');
      });

      await test.step('CA-01.4 direct URLs show Access denied', async () => {
        await assertAccessDenied(page, '/admin/users');
        await assertAccessDenied(page, '/admin/audit');
        await assertAccessDenied(page, '/admin/branches');
        await assertAccessDenied(page, '/admin/settings');
        await assertAccessDenied(page, '/admin/team');
        await assertAccessDenied(page, '/suppliers');
        await assertAccessDenied(page, '/purchasing/orders');
        await assertAccessDenied(page, '/expenses');
        await assertAccessDenied(page, '/reports');
        await assertAccessDenied(page, '/inventory/needs-ordering');
        await assertAccessDenied(page, '/inventory/opening-stock');
      });

      await test.step('CA-01.5 no other-branch records visible through the user token', async () => {
        const token = (await pageToken(page)) ?? (await userToken('cashier'));
        const rows = await dbRows('sales', 'select=id,branch_id&limit=50', token);
        expect(
          rows.every((row) => row.branch_id === process.env.UAT_BRANCH_A_ID),
          'cashier must not see sales from another branch',
        ).toBe(true);
      });
    });
  });

  test('CA-02 shift, discounts, split payment, hold/resume, Rx block, receipt, close', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'cashier', viewport, async (page) => {
      await test.step('CA-02.1 open a shift and assert the DB row', async () => {
        await navigate(page, NAV.shifts);
        await tap(page, 'Start shift');
        await (await field(page, 'Opening cash (ETB)')).fill('100');
        await tap(page, 'Start shift');
        expect(await hasLabel(page, 'Your open shift')).toBe(true);
        expect(await dbCount('shifts', 'cashier_id=not.is.null&status=eq.open')).toBeGreaterThan(0);
        await capture(page, 'CA-02-shift-open');
      });

      await test.step('CA-02.2 customer quick add on the Customers screen', async () => {
        await navigate(page, NAV.customers);
        const name = unique('CA Quick Customer');
        await tap(page, 'Add');
        await (await field(page, 'Name')).fill(name);
        await (await field(page, 'Phone')).fill(`+2519${RUN_ID.slice(-8)}`);
        await tap(page, 'Save');
        expect(await dbCount('customers', `name=eq.${encodeURIComponent(name)}`)).toBe(1);
        await capture(page, 'CA-02-customer-added');
      });

      await test.step('CA-02.3 search, within-limit discount and split payment', async () => {
        await seedStock(process.env.UAT_NORMAL_MEDICINE_ID ?? '', 60, `CASHPRE${RUN_ID}`);
        await navigate(page, NAV.pos);
        const search = await field(page, 'Find medicine by name, SKU or barcode');
        await search.fill(NORMAL_NAME);
        await page.getByText(NORMAL_NAME, { exact: true }).first().click();
        await (await discountField(page)).fill('2');
        await tapMatching(page, /^Pay /);
        await tap(page, 'Add another payment');
        const amounts = page.getByRole('textbox', { name: 'Amount' });
        await amounts.nth(0).fill('2');
        await amounts.nth(1).fill('3');
        const methods = page.getByRole('combobox', { name: 'Method' });
        if ((await methods.count()) >= 2) {
          await methods.nth(1).click();
          await tap(page, 'Mobile money');
        }
        await tapMatching(page, /^Confirm /);
        await expect(page.getByText(/Sale complete/)).toBeVisible();
        const sale = (
          await dbRows('sales', 'order=created_at.desc&limit=1&select=id,invoice_no,discount,total,customer_id')
        )[0];
        expect(Number(sale.discount)).toBeGreaterThan(0);
        const payments = await dbRows('sale_payments', `sale_id=eq.${sale.id}&select=method,amount`);
        expect(payments.length, 'split payment must create two rows').toBe(2);
        await capture(page, 'CA-02-split-sale-receipt');
      });

      await test.step('CA-02.4 discount above the cashier limit is rejected', async () => {
        await navigate(page, NAV.pos);
        const search = await field(page, 'Find medicine by name, SKU or barcode');
        await search.fill(NORMAL_NAME);
        await page.getByText(NORMAL_NAME, { exact: true }).first().click();
        await (await discountField(page)).fill('99');
        await tapMatching(page, /^Pay /);
        await expect(page.getByText(/above your limit/)).toBeVisible();
        expect(await hasButtonMatching(page, /^Confirm /), 'no Confirm button after a rejected discount').toBe(false);
        await capture(page, 'CA-02-discount-limit');
      });

      await test.step('CA-02.5 hold and resume a cart', async () => {
        await navigate(page, NAV.pos);
        const search = await field(page, 'Find medicine by name, SKU or barcode');
        await search.fill(NORMAL_NAME);
        await page.getByText(NORMAL_NAME, { exact: true }).first().click();
        await tap(page, 'Hold');
        await (await field(page, 'Label (e.g. customer name)')).fill(unique('CA held cart'));
        await tap(page, 'Hold');
        await tapMatching(page, /^Held \(/);
        await tap(page, unique('CA held cart'));
        expect(await hasLabel(page, NORMAL_NAME)).toBe(true);
        await capture(page, 'CA-02-hold-resume');
      });

      await test.step('CA-02.6 Rx-only medicine is blocked without a prescription', async () => {
        await seedStock(process.env.UAT_RX_MEDICINE_ID ?? '', 10, `CASHRX${RUN_ID}`);
        await navigate(page, NAV.pos);
        const search = await field(page, 'Find medicine by name, SKU or barcode');
        await search.fill(RX_NAME);
        await page.getByText(RX_NAME, { exact: true }).first().click();
        expect(await hasLabel(page, 'Prescription required')).toBe(true);
        await tapMatching(page, /^Pay /);
        await expect(page.getByText('Select a prescription for this sale.')).toBeVisible();
        await capture(page, 'CA-02-rx-blocked');
      });

      await test.step('CA-02.7 close the shift and assert the Z report numbers', async () => {
        await navigate(page, NAV.shifts);
        await tap(page, 'Close shift');
        await (await field(page, 'Counted cash (ETB)')).fill('110');
        await tap(page, 'Close shift');
        const closed = await dbRows('shifts', 'status=eq.closed&order=closed_at.desc&limit=1&select=id,opening_cash,closing_cash,difference');
        expect(closed.length).toBeGreaterThan(0);
        expect(Number(closed[0]?.opening_cash)).toBe(100);
        expect(Number(closed[0]?.closing_cash)).toBe(110);
        await capture(page, 'CA-02-shift-closed');
      });
    });
  });
});
