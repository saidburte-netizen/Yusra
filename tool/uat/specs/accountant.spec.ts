import { expect, test, type ViewportSize } from '@playwright/test';
import {
  BRANCH_A,
  NAV,
  RUN_ID,
  api,
  assertAccessDenied,
  assertNoLabel,
  button,
  capture,
  choose,
  dbRows,
  field,
  hasLabel,
  navigate,
  rowAction,
  tap,
  unique,
  walkNav,
  withRole,
  type DbRow,
} from '../fixtures/uat';

const today = (): string => new Date().toISOString().slice(0, 10);
const thisMonth = (): string => new Date().toISOString().slice(0, 7);

test.describe('UAT — Accountant', () => {
  test('AC-01 sign in, every nav item, finance-only permissions and direct-URL guards', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'accountant', viewport, async (page) => {
      await test.step('AC-01.1 dashboard landing, nav walk and DB role check', async () => {
        await expect(page).toHaveURL(/\/dashboard$/);
        expect(await hasLabel(page, NAV.dashboard)).toBe(true);
        await walkNav(page, 'accountant');
        const profile = await dbRows(
          'profiles',
          `email=eq.uat_${RUN_ID}_accountant@yusra.test&select=role,branch_id,is_active`,
        );
        expect(profile.length).toBe(1);
        expect(profile[0]?.role).toBe('accountant');
        expect(profile[0]?.branch_id).toBe(BRANCH_A);
        expect(profile[0]?.is_active).toBe(true);
        await capture(page, 'AC-01-dashboard-and-nav');
      });

      await test.step('AC-01.2 finance modules are present but admin modules are hidden', async () => {
        for (const label of [NAV.expenses, NAV.reports, NAV.sales, NAV.purchasing]) {
          expect(await hasLabel(page, label), `${label} must be visible to an accountant`).toBe(true);
        }
        for (const label of [
          NAV.pos,
          NAV.prescriptions,
          NAV.users,
          NAV.team,
          NAV.branches,
          NAV.settings,
          NAV.audit,
        ]) {
          await assertNoLabel(page, label);
        }
        await capture(page, 'AC-01-finance-only-nav');
      });

      await test.step('AC-01.3 direct URLs for non-finance modules are Access denied', async () => {
        for (const path of [
          '/pos',
          '/prescriptions',
          '/admin/users',
          '/admin/team',
          '/admin/branches',
          '/admin/settings',
          '/admin/audit',
        ]) {
          await assertAccessDenied(page, path);
        }
      });
    });
  });

  test('AC-02 expense entry and approval, finance reports, exports and DB agreement', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'accountant', viewport, async (page) => {
      const description = unique('AC Expense');
      const pendingDescription = unique('AC Pending Expense');

      await test.step('AC-02.1 add an expense through the UI and assert the DB row', async () => {
        await navigate(page, NAV.expenses);
        await tap(page, 'Add');
        await (await field(page, 'Amount')).fill('12.50');
        await choose(page, 'Category', 'Other');
        await choose(page, 'Payment method', 'Cash');
        await (await field(page, 'Description')).fill(description);
        await tap(page, 'Save');
        expect(await hasLabel(page, description), 'new expense must be visible in the UI').toBe(true);
        const rows = await dbRows(
          'expenses',
          `description=eq.${encodeURIComponent(description)}&select=id,amount,status,branch_id,expense_date`,
        );
        expect(rows.length).toBe(1);
        expect(Number(rows[0]?.amount)).toBe(12.5);
        expect(rows[0]?.branch_id).toBe(BRANCH_A);
        expect(String(rows[0]?.expense_date)).toContain(thisMonth());
        await capture(page, 'AC-02-expense-created');
      });

      await test.step('AC-02.2 approve a pending expense through the UI', async () => {
        // A pending row is seeded over PostgREST: the app creates expenses as
        // approved, so this exercises the approval workflow itself.
        const created = await api<DbRow[]>('expenses', {
          method: 'POST',
          prefer: 'return=representation',
          body: {
            branch_id: BRANCH_A,
            category: 'Utilities',
            description: pendingDescription,
            amount: 7.25,
            expense_date: today(),
            payment_method: 'bank_transfer',
            status: 'pending',
          },
        });
        expect(created.status, created.text).toBe(201);
        await navigate(page, NAV.expenses);
        expect(await hasLabel(page, pendingDescription)).toBe(true);
        await rowAction(page, pendingDescription, 'Approve');
        const rows = await dbRows(
          'expenses',
          `description=eq.${encodeURIComponent(pendingDescription)}&select=id,status`,
        );
        expect(rows[0]?.status, 'pending expense must be approved in the DB').toBe('approved');
        await capture(page, 'AC-02-expense-approved');
      });

      await test.step('AC-02.3 open finance reports and check the report views', async () => {
        await navigate(page, NAV.reports);
        for (const title of ['Sales summary by day', 'Expenses', 'Net profit statement']) {
          await tap(page, title);
          expect(await hasLabel(page, title), `${title} must render`).toBe(true);
          await capture(page, `AC-02-report-${title.replace(/\W+/g, '-')}`);
        }
        const expenses = await dbRows(
          'v_report_expenses',
          `branch_id=eq.${BRANCH_A}&date=gte.${thisMonth()}-01&date=lte.${thisMonth()}-31&select=date,category,amount`,
        );
        const total = expenses.reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
        expect(total, 'both new expenses must appear in v_report_expenses').toBeGreaterThanOrEqual(19.75);
        const net = await dbRows(
          'v_report_net_profit',
          `branch_id=eq.${BRANCH_A}&period=eq.${thisMonth()}&select=period,revenue,expenses,net&limit=1`,
        );
        expect(net.length).toBe(1);
        const revenue = Number(net[0]?.revenue ?? 0);
        const spent = Number(net[0]?.expenses ?? 0);
        expect(spent).toBeGreaterThanOrEqual(19.75);
        expect(Math.abs(Number(net[0]?.net ?? 0) - (revenue - spent))).toBeLessThan(0.01);
      });

      await test.step('AC-02.4 export affordance and read-only operational screens', async () => {
        await navigate(page, NAV.expenses);
        const exportButton = await button(page, 'Export CSV');
        expect(exportButton, 'expenses table must offer CSV export').not.toBeNull();
        await exportButton!.click();
        await expect(page.locator('body')).not.toContainText('Something went wrong');
        await capture(page, 'AC-02-expense-export');

        await navigate(page, NAV.inventory);
        expect(await button(page, 'New medicine')).toBeNull();
        await navigate(page, NAV.purchasing);
        expect(await button(page, 'New purchase order')).toBeNull();
        await capture(page, 'AC-02-operational-readonly');
      });
    });
  });
});
