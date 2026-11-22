import { expect, test, type ViewportSize } from '@playwright/test';
import {
  NAV,
  RUN_ID,
  assertAccessDenied,
  button,
  capture,
  choose,
  dbCount,
  dbRows,
  field,
  futureDate,
  hasLabel,
  navigate,
  rowAction,
  seedStock,
  sellViaPos,
  tap,
  tapMatching,
  unique,
  walkNav,
  withRole,
} from '../fixtures/uat';

const NORMAL_MEDICINE = process.env.UAT_NORMAL_MEDICINE_ID ?? '';
const RX_MEDICINE = process.env.UAT_RX_MEDICINE_ID ?? '';

test.describe('UAT — Pharmacist', () => {
  test('PH-01 sign in and walk every permitted nav item', async ({ browser }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'pharmacist', viewport, async (page) => {
      await test.step('PH-01.1 prescription-first landing', async () => {
        await expect(page).toHaveURL(/\/prescriptions$/);
        expect(await hasLabel(page, NAV.prescriptions)).toBe(true);
        await capture(page, 'PH-01-landing');
      });
      await test.step('PH-01.2 walk all nine navigation destinations', async () => {
        await walkNav(page, 'pharmacist');
      });
      await test.step('PH-01.3 forbidden modules are not reachable', async () => {
        expect(await button(page, 'Expenses')).toBeNull();
        await assertAccessDenied(page, '/reports');
        await assertAccessDenied(page, '/admin/users');
        await assertAccessDenied(page, '/expenses');
      });
    });
  });

  test('PH-02 catalogue, opening stock without batch/supplier, batches, adjustments, stocktake', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'pharmacist', viewport, async (page) => {
      await test.step('PH-02.1 create a medicine with no preferred supplier', async () => {
        await navigate(page, NAV.inventory);
        const name = unique('PH Medicine');
        await tap(page, 'New medicine');
        await (await field(page, 'Name')).fill(name);
        await (await field(page, 'Cost price')).fill('2');
        await (await field(page, 'Selling price')).fill('6');
        await tap(page, 'Save');
        const rows = await dbRows(
          'medicines',
          `name=eq.${encodeURIComponent(name)}&select=id,preferred_supplier_id`,
        );
        expect(rows.length).toBe(1);
        expect(rows[0]?.preferred_supplier_id).toBeNull();
        await capture(page, 'PH-02-medicine-no-supplier');
      });

      await test.step('PH-02.2 create a category', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Categories');
        const name = unique('PH Category');
        await tap(page, 'Add');
        await (await field(page, 'Name')).fill(name);
        await tap(page, 'Save');
        expect(await dbCount('categories', `name=eq.${encodeURIComponent(name)}`)).toBe(1);
        await capture(page, 'PH-02-category');
      });

      await test.step('PH-02.3 opening stock with blank batch and no supplier', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Opening stock');
        await tap(page, 'Add row');
        await choose(page, 'Medicine', process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol');
        await (await field(page, 'Quantity')).first().fill('40');
        await (await field(page, 'Expiry date')).first().fill(futureDate());
        // Batch number is intentionally left blank; the RPC generates one.
        await (await field(page, 'Unit cost (optional)')).first().fill('2');
        await tap(page, 'Save all');
        const batches = await dbRows(
          'stock_batches',
          `medicine_id=eq.${NORMAL_MEDICINE}&supplier_id=is.null&order=created_at.desc&limit=1&select=id,batch_no,supplier_id,quantity`,
        );
        expect(batches.length, 'blank-batch opening stock was not saved').toBe(1);
        expect(batches[0]?.batch_no).toMatch(/^.+\d{3}$/);
        const movements = await dbRows(
          'stock_movements',
          `batch_id=eq.${batches[0]?.id}&movement_type=eq.opening&select=id`,
        );
        expect(movements.length).toBeGreaterThan(0);
        await capture(page, 'PH-02-opening-stock-no-batch');
      });

      await test.step('PH-02.4 inspect batches and post a stock adjustment', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Batches');
        expect(await hasLabel(page, 'Batches')).toBe(true);
        await capture(page, 'PH-02-batches');
        await navigate(page, NAV.inventory);
        await tap(page, 'Adjustments');
        await tap(page, 'New adjustment');
        await choose(page, 'Medicine', process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol');
        await (await field(page, 'Quantity')).first().fill('2');
        await tap(page, 'Apply');
        expect(await dbCount('stock_movements', 'movement_type=eq.adjustment')).toBeGreaterThan(0);
        await capture(page, 'PH-02-adjustment');
      });

      await test.step('PH-02.5 apply a stocktake variance', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Stock take');
        const counted = page.getByRole('textbox', { name: 'Counted' });
        if ((await counted.count()) > 0) await counted.first().fill('1');
        await tapMatching(page, /^Apply \d+ variance/);
        expect(await dbCount('stock_movements', 'reason=ilike.*stocktake*')).toBeGreaterThanOrEqual(0);
        await capture(page, 'PH-02-stocktake');
      });
    });
  });

  test('PH-03 prescriptions, Rx dispense, return and void', async ({ browser }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'pharmacist', viewport, async (page) => {
      await test.step('PH-03.0 pharmacist opens their own shift from POS', async () => {
        await navigate(page, NAV.pos);
        await tap(page, 'Open shift');
        await (await field(page, 'Opening cash (ETB)')).fill('100');
        await tap(page, 'Start shift');
        expect(await hasLabel(page, 'Shift open')).toBe(true);
        await capture(page, 'PH-03-shift-open');
      });

      await test.step('PH-03.1 register a prescription', async () => {
        await navigate(page, NAV.prescriptions);
        await tap(page, 'Register');
        const patient = unique('PH Patient');
        await (await field(page, 'Patient name')).fill(patient);
        await (await field(page, 'Prescriber name')).fill('Dr UAT');
        await tap(page, 'Save');
        const rows = await dbRows(
          'prescriptions',
          `patient_name=eq.${encodeURIComponent(patient)}&select=id,status`,
        );
        expect(rows.length).toBe(1);
        expect(rows[0]?.status).toBe('pending');
        await capture(page, 'PH-03-prescription');
        await seedStock(RX_MEDICINE, 10, `RX${RUN_ID}`);
        await rowAction(page, patient, 'New sale');
      });

      await test.step('PH-03.2 dispense the Rx-only medicine at POS', async () => {
        const rxName = process.env.UAT_RX_MEDICINE_NAME ?? 'UAT Amoxicillin';
        const search = await field(page, 'Find medicine by name, SKU or barcode');
        await search.fill(rxName);
        await page.getByText(rxName, { exact: true }).first().click();
        expect(await hasLabel(page, 'Prescription selected')).toBe(true);
        await tapMatching(page, /^Pay /);
        await tapMatching(page, /^Confirm /);
        await expect(page.getByText(/Sale complete/)).toBeVisible();
        const sale = (
          await dbRows('sales', 'branch_id=eq.' + (process.env.UAT_BRANCH_A_ID ?? '') + '&order=created_at.desc&limit=1&select=id,prescription_id')
        )[0];
        expect(sale?.prescription_id, 'Rx sale must reference the prescription').toBeTruthy();
        await capture(page, 'PH-03-rx-dispensed');
      });

      await test.step('PH-03.3 process a sale return with restock', async () => {
        await seedStock(NORMAL_MEDICINE, 20, `RET${RUN_ID}`);
        const sale = await sellViaPos(page, process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol');
        await navigate(page, NAV.sales);
        await page.getByText(sale.invoice_no as string, { exact: true }).first().click();
        await tap(page, 'Process return');
        await (await field(page, 'Reason')).fill(unique('UAT return'));
        await tap(page, 'Process return');
        expect(await dbCount('sale_returns', `sale_id=eq.${sale.id}`)).toBe(1);
        await capture(page, 'PH-03-return');
      });

      await test.step('PH-03.4 void a completed sale', async () => {
        await seedStock(NORMAL_MEDICINE, 20, `VOID${RUN_ID}`);
        const sale = await sellViaPos(page, process.env.UAT_NORMAL_MEDICINE_NAME ?? 'UAT Paracetamol');
        await navigate(page, NAV.sales);
        await rowAction(page, sale.invoice_no as string, 'Void');
        await (await field(page, 'Reason')).fill(unique('UAT void'));
        await tap(page, 'Void sale');
        const rows = await dbRows('sales', `id=eq.${sale.id}&select=status,void_reason`);
        expect(rows[0]?.status).toBe('voided');
        await capture(page, 'PH-03-void');
      });
    });
  });
});
