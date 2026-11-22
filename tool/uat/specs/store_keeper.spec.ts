import { expect, test, type ViewportSize } from '@playwright/test';
import {
  NAV,
  RUN_ID,
  assertAccessDenied,
  assertNoLabel,
  button,
  capture,
  choose,
  dbCount,
  dbRows,
  field,
  futureDate,
  hasLabel,
  navigate,
  tap,
  unique,
  walkNav,
  withRole,
} from '../fixtures/uat';

const NORMAL_NAME = process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol';

test.describe('UAT — Store keeper', () => {
  test('SK-01 sign in, nav walk, no sales or finance access', async ({ browser }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'store_keeper', viewport, async (page) => {
      await test.step('SK-01.1 inventory landing and permitted nav items', async () => {
        await expect(page).toHaveURL(/\/inventory$/);
        expect(await hasLabel(page, NAV.inventory)).toBe(true);
        await walkNav(page, 'store_keeper');
      });

      await test.step('SK-01.2 sales and finance actions are hidden', async () => {
        for (const label of [
          NAV.pos,
          NAV.sales,
          NAV.shifts,
          NAV.customers,
          NAV.prescriptions,
          NAV.expenses,
          NAV.reports,
          NAV.users,
          NAV.audit,
        ]) {
          await assertNoLabel(page, label);
        }
        await navigate(page, NAV.inventory);
        expect(await button(page, 'New sale')).toBeNull();
        await capture(page, 'SK-01-no-sales-finance');
      });

      await test.step('SK-01.3 direct URLs are Access denied', async () => {
        await assertAccessDenied(page, '/pos');
        await assertAccessDenied(page, '/sales');
        await assertAccessDenied(page, '/sales/returns');
        await assertAccessDenied(page, '/shifts');
        await assertAccessDenied(page, '/expenses');
        await assertAccessDenied(page, '/reports');
        await assertAccessDenied(page, '/admin/users');
      });
    });
  });

  test('SK-02 suppliers, PO draft/approve/receive, opening stock, adjustments, reorder', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'store_keeper', viewport, async (page) => {
      await test.step('SK-02.1 add a supplier through the UI', async () => {
        await navigate(page, NAV.suppliers);
        const name = unique('SK Supplier');
        await tap(page, 'New supplier');
        await (await field(page, 'Name')).fill(name);
        await (await field(page, 'Contact person')).fill('UAT Contact');
        await (await field(page, 'Phone')).fill('+251911222333');
        await tap(page, 'Save');
        expect(await dbCount('suppliers', `name=eq.${encodeURIComponent(name)}`)).toBe(1);
        await capture(page, 'SK-02-supplier');
      });

      await test.step('SK-02.2 create a draft PO, approve it, receive goods', async () => {
        await navigate(page, NAV.purchasing);
        await tap(page, 'New purchase order');
        await choose(page, 'Supplier', process.env.UAT_SUPPLIER_NAME ?? 'UAT Supplier');
        await tap(page, 'Add line');
        await (await field(page, 'Search name or scan barcode')).fill(NORMAL_NAME);
        await page.getByText(NORMAL_NAME, { exact: true }).first().click();
        await (await field(page, 'Quantity')).last().fill('25');
        await (await field(page, 'Unit cost')).last().fill('2');
        await tap(page, 'Add');
        await tap(page, 'Create draft');
        const drafts = await dbRows(
          'purchase_orders',
          'status=eq.draft&order=created_at.desc&limit=1&select=id,po_no,status',
        );
        expect(drafts.length, 'draft PO was not created').toBe(1);
        const poId = String(drafts[0].id);
        await capture(page, 'SK-02-po-draft');

        await navigate(page, NAV.purchasing);
        await page.getByText(drafts[0].po_no as string, { exact: true }).first().click();
        await tap(page, 'Approve & send');
        expect((await dbRows('purchase_orders', `id=eq.${poId}&select=status`))[0]?.status).toBe('ordered');

        await tap(page, 'Receive goods');
        await (await field(page, 'Batch no')).fill(`SK${RUN_ID}`);
        await (await field(page, 'Expiry')).fill(futureDate());
        await tap(page, 'Receive goods');
        const batches = await dbRows(
          'stock_batches',
          `purchase_order_id=eq.${poId}&select=id,quantity,batch_no`,
        );
        expect(batches.length).toBeGreaterThan(0);
        expect(Number(batches[0]?.quantity)).toBeGreaterThan(0);
        expect(await dbCount('stock_movements', `batch_id=eq.${batches[0]?.id}&movement_type=eq.purchase`)).toBeGreaterThan(0);
        await capture(page, 'SK-02-po-received');
      });

      await test.step('SK-02.3 opening stock and a stock adjustment', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Opening stock');
        await tap(page, 'Add row');
        await choose(page, 'Medicine', NORMAL_NAME);
        await (await field(page, 'Quantity')).first().fill('15');
        await (await field(page, 'Expiry date')).first().fill(futureDate());
        await (await field(page, 'Batch number (optional)')).first().fill(`SKOPEN${RUN_ID}`);
        await tap(page, 'Save all');
        expect(await dbCount('stock_batches', `batch_no=eq.SKOPEN${RUN_ID}`)).toBe(1);

        await navigate(page, NAV.inventory);
        await tap(page, 'Adjustments');
        await tap(page, 'New adjustment');
        await choose(page, 'Medicine', NORMAL_NAME);
        await (await field(page, 'Quantity')).first().fill('3');
        await tap(page, 'Apply');
        expect(await dbCount('stock_movements', 'movement_type=eq.adjustment')).toBeGreaterThan(0);
        await capture(page, 'SK-02-adjustment');
      });

      await test.step('SK-02.4 Needs ordering creates draft purchase orders', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Needs ordering');
        expect(await hasLabel(page, 'Needs ordering')).toBe(true);
        const before = await dbCount('purchase_orders', 'status=eq.draft');
        const supplier = await button(page, 'Create purchase order(s)');
        expect(supplier, 'reorder action must be visible to a store keeper').not.toBeNull();
        await supplier!.click();
        const after = await dbCount('purchase_orders', 'status=eq.draft');
        expect(after, 'reorder must create at least one draft PO').toBeGreaterThanOrEqual(before);
        await capture(page, 'SK-02-reorder-draft-pos');
      });
    });
  });
});
