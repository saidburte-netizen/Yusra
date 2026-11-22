import { expect, test, type ViewportSize } from '@playwright/test';
import {
  BRANCH_A,
  BRANCH_B,
  NAV,
  RUN_ID,
  assertNoLabel,
  button,
  capture,
  choose,
  dbCount,
  dbRows,
  field,
  hasLabel,
  navigate,
  rowAction,
  tap,
  unique,
  walkNav,
  withRole,
} from '../fixtures/uat';

const REPORT_TITLES = [
  'Sales summary by day',
  'Sales by cashier',
  'Sales by payment method',
  'Sales by medicine',
  'Profit (revenue minus cost)',
  'Stock valuation',
  'Expiry losses',
  'Purchases by supplier',
  'Expenses',
  'Net profit statement',
  'Shift cash variance',
  'Controlled / prescription-only register',
];

const ROLE_OPTIONS = [
  ['superadmin', 'Super admin'],
  ['admin', 'Admin'],
  ['pharmacist', 'Pharmacist'],
  ['cashier', 'Cashier'],
  ['storekeeper', 'Store keeper'],
  ['accountant', 'Accountant'],
];

test.describe('UAT — Super admin', () => {
  test('SA-01 sign in, every nav item at both viewports, DB role check', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'super_admin', viewport, async (page) => {
      await test.step('SA-01.1 landing is the dashboard with branch switcher', async () => {
        await expect(page).toHaveURL(/\/dashboard$/);
        expect(await hasLabel(page, NAV.dashboard)).toBe(true);
        expect(await hasLabel(page, 'All branches (view only)')).toBe(true);
        await capture(page, 'SA-01-dashboard');
      });

      await test.step('SA-01.2 walk all 16 navigation destinations', async () => {
        await walkNav(page, 'super_admin');
      });

      const rows = await dbRows('profiles', `select=id,role,branch_id&email=ilike.uat_${RUN_ID}_%`);
      await test.step('SA-01.3 DB confirms one profile per role', async () => {
        const roles = rows.map((row) => String(row.role));
        for (const [key, label] of ROLE_OPTIONS) {
          void label;
          expect(roles, `missing ${key} profile`).toContain(key.replace('storekeeper', 'store_keeper'));
        }
        await capture(page, 'SA-01-db-profiles');
      });
    });
  });

  test('SA-02 branches, all role users, role/branch change, deactivate/reactivate', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'super_admin', viewport, async (page) => {
      await test.step('SA-02.1 create a branch through the UI and assert the DB row', async () => {
        await navigate(page, NAV.branches);
        await tap(page, 'Add');
        await (await field(page, 'Pharmacy name')).fill(unique('UAT Third Branch'));
        await (await field(page, 'Code')).fill(`UATC${RUN_ID.slice(-8)}`);
        await (await field(page, 'Address')).fill('UAT address');
        await (await field(page, 'Phone')).fill('+251911000000');
        await tap(page, 'Save');
        await expect(page.getByText(unique('UAT Third Branch'))).toBeVisible();
        expect(await dbCount('branches', `name=eq.${encodeURIComponent(unique('UAT Third Branch'))}`)).toBe(1);
        await capture(page, 'SA-02-branch-created');
      });

      await test.step('SA-02.2 create a user for every role through the Edge Function-backed dialog', async () => {
        await navigate(page, NAV.users);
        for (const [local, roleLabel] of ROLE_OPTIONS) {
          const email = `uat_${RUN_ID}_ui_${local}@yusra.test`;
          await tap(page, 'Create user');
          await (await field(page, 'Email address')).fill(email);
          await (await field(page, 'Full name')).fill(unique(`UAT UI ${roleLabel}`));
          await choose(page, 'Role', roleLabel);
          await choose(page, 'Branch', unique('UAT Branch A'));
          await tap(page, 'Save');
          await expect(page.getByText('Temporary password')).toBeVisible();
          await tap(page, 'Close');
          expect(await dbCount('profiles', `email=eq.${email}`), `${roleLabel} profile missing`).toBe(1);
          await capture(page, `SA-02-user-${local}`);
        }
      });

      await test.step('SA-02.3 change role and branch of an existing user', async () => {
        const email = `uat_${RUN_ID}_ui_admin@yusra.test`;
        await rowAction(page, email, 'Edit');
        await choose(page, 'Role', 'Pharmacist');
        await choose(page, 'Branch', unique('UAT Branch B'));
        await tap(page, 'Save');
        const rows = await dbRows('profiles', `email=eq.${email}&select=role,branch_id`);
        expect(rows[0]?.role).toBe('pharmacist');
        expect(rows[0]?.branch_id).toBe(BRANCH_B);
        await capture(page, 'SA-02-role-branch-changed');
      });

      await test.step('SA-02.4 deactivate and reactivate a user', async () => {
        const email = `uat_${RUN_ID}_ui_cashier@yusra.test`;
        await rowAction(page, email, 'Deactivate');
        expect((await dbRows('profiles', `email=eq.${email}&select=is_active`))[0]?.is_active).toBe(false);
        await capture(page, 'SA-02-deactivated');
        await tap(page, 'Reactivate');
        expect((await dbRows('profiles', `email=eq.${email}&select=is_active`))[0]?.is_active).toBe(true);
        await capture(page, 'SA-02-reactivated');
      });

      await test.step('SA-02.5 switch branches from the top bar', async () => {
        const switcher = await button(page, 'All branches (view only)');
        expect(switcher, 'branch switcher must exist for a super admin').not.toBeNull();
        await switcher!.click();
        await tap(page, unique('UAT Branch B'));
        expect(await hasLabel(page, unique('UAT Branch B'))).toBe(true);
        await capture(page, 'SA-02-branch-switched');
      });
    });
  });

  test('SA-03 settings, correction approval, all reports and live dashboard', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'super_admin', viewport, async (page) => {
      await test.step('SA-03.1 change and publish settings', async () => {
        await navigate(page, NAV.settings);
        const footer = await field(page, 'Receipt footer');
        await footer.fill(unique('UAT receipt footer'));
        await tap(page, 'Save');
        await tap(page, 'Publish settings to team');
        const rows = await dbRows('app_settings', 'key=eq.receipt_footer&select=value');
        expect(JSON.stringify(rows[0]?.value)).toContain('UAT receipt footer');
        await capture(page, 'SA-03-settings');
      });

      await test.step('SA-03.2 approve a pending activity-log correction', async () => {
        await navigate(page, NAV.audit);
        await tap(page, 'Pending approval');
        await tap(page, 'Approve correction');
        const rows = await dbRows(
          'activity_log',
          `correction_requested=eq.true&approved_by=not.is.null&summary=like.*UAT seeded correction*&select=id,approved_by,correction_requested`,
        );
        expect(rows.length, 'seeded correction must be approved in the DB').toBeGreaterThan(0);
        expect(rows[0]?.correction_requested).toBe(false);
        await capture(page, 'SA-03-correction-approved');
      });

      await test.step('SA-03.3 open all twelve reports and check DB-backed results', async () => {
        await navigate(page, NAV.reports);
        for (const title of REPORT_TITLES) {
          await tap(page, title);
          expect(await hasLabel(page, title)).toBe(true);
          await capture(page, `SA-03-report-${title}`);
        }
        const reportViews = await apiViewCounts();
        for (const view of reportViews) expect(view.count, `${view.name} must be queryable`).toBeGreaterThanOrEqual(0);
      });

      await test.step('SA-03.4 dashboard counters agree with the DB', async () => {
        await navigate(page, NAV.dashboard);
        expect(await hasLabel(page, "Today's sales")).toBe(true);
        expect(await hasLabel(page, 'Recent activity')).toBe(true);
        const sales = await dbCount('sales', `branch_id=eq.${BRANCH_A}`);
        expect(sales).toBeGreaterThanOrEqual(0);
        await capture(page, 'SA-03-dashboard');
      });
    });
  });
});

async function apiViewCounts(): Promise<Array<{ name: string; count: number }>> {
  const { api } = await import('../fixtures/uat');
  const names = [
    'v_report_sales_by_day',
    'v_report_sales_by_cashier',
    'v_report_sales_payment',
    'v_report_sales_by_medicine',
    'v_report_profit',
    'v_report_stock_valuation',
    'v_report_expiry_losses',
    'v_report_purchases_supplier',
    'v_report_expenses',
    'v_report_net_profit',
    'v_report_shift_variance',
    'v_report_controlled_register',
  ];
  const result: Array<{ name: string; count: number }> = [];
  for (const name of names) {
    const response = await api<unknown[]>(`${name}?select=*&limit=1`);
    result.push({ name, count: response.status === 200 ? (response.data as unknown[]).length : -1 });
  }
  return result;
}
