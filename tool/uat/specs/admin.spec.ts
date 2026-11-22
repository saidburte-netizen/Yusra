import { expect, test, type ViewportSize } from '@playwright/test';
import {
  BRANCH_A,
  NAV,
  RUN_ID,
  assertNoLabel,
  button,
  capture,
  combobox,
  dbCount,
  dbRows,
  field,
  field as formField,
  hasLabel,
  navigate,
  tap,
  unique,
  walkNav,
  withRole,
} from '../fixtures/uat';

test.describe('UAT — Admin (own branch only)', () => {
  test('AD-01 sign in, full nav, no super-admin creation, no cross-branch edits', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'admin', viewport, async (page) => {
      await test.step('AD-01.1 dashboard landing and every permitted nav item', async () => {
        await expect(page).toHaveURL(/\/dashboard$/);
        await walkNav(page, 'admin');
        expect(await dbCount('profiles', `branch_id=eq.${BRANCH_A}&is_active=eq.true`)).toBeGreaterThan(0);
      });

      await test.step('AD-01.2 create-user dialog hides Super admin and other branches', async () => {
        await navigate(page, NAV.users);
        await tap(page, 'Create user');
        const roleSelect = await combobox(page, 'Role');
        await roleSelect.click();
        expect(await hasLabel(page, 'Super admin'), 'admin must not be able to grant super_admin').toBe(false);
        const branchSelect = await combobox(page, 'Branch');
        await branchSelect.click();
        expect(await hasLabel(page, unique('UAT Branch B')), 'other branch must not be selectable').toBe(false);
        expect(await hasLabel(page, unique('UAT Branch A'))).toBe(true);
        await capture(page, 'AD-01-create-user-guard');
        await tap(page, 'Cancel');

        const superAdmins = await dbCount('profiles', `role=eq.super_admin&email=like.uat_${RUN_ID}_ui_%`);
        expect(superAdmins, 'admin created a super admin in the DB').toBe(0);
      });

      await test.step('AD-01.3 branches and team access are read-only for admin', async () => {
        await navigate(page, NAV.branches);
        expect(await button(page, 'Add'), 'admin must not see Add branch').toBeNull();
        await capture(page, 'AD-01-branches-readonly');
        await navigate(page, NAV.team);
        expect(await button(page, 'Share my access'), 'admin must not see Share my access').toBeNull();
        expect(await button(page, 'Edit role / branch'), 'admin must not see Edit role / branch').toBeNull();
        await capture(page, 'AD-01-team-readonly');
      });

      await test.step('AD-01.4 cross-branch user is untouched', async () => {
        const other = await dbRows(
          'profiles',
          `email=eq.uat_${RUN_ID}_adminother@yusra.test&select=branch_id,role,is_active`,
        );
        expect(other[0]?.branch_id).toBe(process.env.UAT_BRANCH_B_ID);
        expect(other[0]?.role).toBe('admin');
        await capture(page, 'AD-01-cross-branch-unchanged');
      });
    });
  });

  test('AD-02 daily work inside the own branch: catalogue, settings, reports', async ({
    browser,
  }, testInfo) => {
    const viewport = testInfo.project.use.viewport as ViewportSize;
    await withRole(browser, 'admin', viewport, async (page) => {
      await test.step('AD-02.1 create a category and a supplier-less medicine through the UI', async () => {
        await navigate(page, NAV.inventory);
        await tap(page, 'Categories');
        await tap(page, 'Add');
        const categoryName = unique('AD Category');
        await (await formField(page, 'Name')).fill(categoryName);
        await tap(page, 'Save');
        expect(await dbCount('categories', `name=eq.${encodeURIComponent(categoryName)}`)).toBe(1);

        await navigate(page, NAV.inventory);
        const medicineName = unique('AD Medicine');
        await tap(page, 'New medicine');
        await (await formField(page, 'Name')).fill(medicineName);
        await (await formField(page, 'Cost price')).fill('3');
        await (await formField(page, 'Selling price')).fill('7');
        // Deliberately leave "Preferred supplier" as None: medicines may have
        // no supplier (pharmacist journey asserts the same).
        await tap(page, 'Save');
        const rows = await dbRows(
          'medicines',
          `name=eq.${encodeURIComponent(medicineName)}&select=id,preferred_supplier_id`,
        );
        expect(rows.length).toBe(1);
        expect(rows[0]?.preferred_supplier_id, 'medicine must be creatable without a supplier').toBeNull();
        await capture(page, 'AD-02-medicine-no-supplier');
      });

      await test.step('AD-02.2 settings + reports + dashboard stay branch scoped', async () => {
        await navigate(page, NAV.settings);
        await (await field(page, 'Receipt footer')).fill(unique('AD footer'));
        await tap(page, 'Save');
        await navigate(page, NAV.reports);
        expect(await hasLabel(page, 'Sales summary by day')).toBe(true);
        await navigate(page, NAV.dashboard);
        expect(await hasLabel(page, "Today's sales")).toBe(true);
        const sales = await dbCount('sales', `branch_id=eq.${BRANCH_A}`);
        expect(sales).toBeGreaterThanOrEqual(0);
        await capture(page, 'AD-02-dashboard');
      });

      await test.step('AD-02.3 no branch switcher for a non-super-admin', async () => {
        await assertNoLabel(page, 'All branches (view only)');
        await assertNoLabel(page, 'Manage branches');
        await capture(page, 'AD-02-no-branch-switcher');
      });
    });
  });
});
