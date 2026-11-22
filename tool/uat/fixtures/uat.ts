/* eslint-disable no-console */
import fs from 'node:fs';
import path from 'node:path';
import {
  expect,
  test,
  type Browser,
  type BrowserContext,
  type Locator,
  type Page,
  type ViewportSize,
} from '@playwright/test';
import usersJson from './users.json';

// ---------------------------------------------------------------------------
// Configuration, seeded fixture users and helpers.
// No credential value is ever written to a file or printed by these helpers.
// ---------------------------------------------------------------------------

export type Role =
  | 'super_admin'
  | 'admin'
  | 'pharmacist'
  | 'cashier'
  | 'store_keeper'
  | 'accountant';

interface UatUser {
  key: string;
  role: Role;
  branch: 'A' | 'B';
  local: string;
  password: string;
  fullName: string;
}

export const USERS = usersJson as UatUser[];
export const RUN_ID = process.env.UAT_RUN_ID ?? 'nodemo';
export const SUPABASE_URL = process.env.UAT_SUPABASE_URL ?? '';
export const ANON_KEY = process.env.UAT_ANON_KEY ?? '';
export const SERVICE_KEY = process.env.UAT_SERVICE_KEY ?? '';
export const BRANCH_A = process.env.UAT_BRANCH_A_ID ?? '';
export const BRANCH_B = process.env.UAT_BRANCH_B_ID ?? '';
export const ARTIFACTS = path.resolve(__dirname, '..', 'artifacts');

export function userFor(key: string): UatUser {
  const user = USERS.find((entry) => entry.key === key);
  if (!user) throw new Error(`Unknown UAT fixture user: ${key}`);
  return user;
}

export function emailFor(key: string): string {
  const user = userFor(key);
  return `uat_${RUN_ID}_${user.local}@yusra.test`;
}

export function unique(label: string): string {
  return `${label} ${RUN_ID}`;
}

// ---------------------------------------------------------------------------
// Browser session helpers.
// ---------------------------------------------------------------------------

/** Runs a journey in a fresh, isolated browser context for one role. */
export async function withRole(
  browser: Browser,
  key: string,
  viewport: ViewportSize | undefined,
  journey: (page: Page) => Promise<void>,
): Promise<void> {
  const { context, page } = await openRole(browser, key, viewport);
  try {
    await journey(page);
  } finally {
    await context.close();
  }
}

export async function openRole(
  browser: Browser,
  key: string,
  viewport?: ViewportSize,
): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext({
    viewport: viewport ?? { width: 1440, height: 900 },
    locale: 'en-US',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(20_000);
  await login(page, key);
  return { context, page };
}

/** Logs in through the real LoginScreen (UI only — no token injection). */
export async function login(page: Page, key: string): Promise<void> {
  await page.goto('/login');
  const email = await field(page, 'Email address');
  const password = await field(page, 'Password');
  await email.fill(emailFor(key));
  await password.fill(userFor(key).password);
  await tap(page, 'Sign in');
  await expect(page, 'login must redirect away from /login').not.toHaveURL(/\/login$/);
  await expect(page.locator('body')).not.toContainText('Email or password is incorrect.');
}

export async function signOut(page: Page, key: string): Promise<void> {
  // The avatar popup's tooltip is the signed-in user's full name.
  const fullName = userFor(key).fullName;
  const popup = await firstVisible([
    page.getByRole('button', { name: fullName }),
    page.locator(`[aria-label="${fullName}"]`),
    page.locator('header button').last(),
  ]);
  if (!popup) throw new Error(`No avatar menu button found while signing out ${key}`);
  await popup.click();
  await tap(page, 'Sign out');
  await expect(page).toHaveURL(/\/login$/);
}

// ---------------------------------------------------------------------------
// Resilient locators for Flutter web's semantics tree.
//
// Flutter web emits semantics nodes with role/aria-label only when
// accessibility is requested (playwright.config.ts forces it on). These
// helpers try the accessible locator first and fall back to the label text so
// a renderer change does not silently invalidate a whole journey.
// ---------------------------------------------------------------------------

async function firstVisible(candidates: Locator[]): Promise<Locator | null> {
  for (const locator of candidates) {
    try {
      if ((await locator.count()) > 0 && (await locator.first().isVisible())) {
        return locator.first();
      }
    } catch {
      // A candidate may target a node that disappeared between checks.
    }
  }
  return null;
}

export async function field(page: Page, label: string): Promise<Locator> {
  const locator = await firstVisible([
    page.getByRole('textbox', { name: label }),
    page.getByLabel(label, { exact: true }),
    page.locator(`[aria-label="${label}"]`),
    page.getByText(label, { exact: true }).locator('..').locator('input, textarea'),
  ]);
  if (!locator) throw new Error(`No form field found for "${label}"`);
  return locator;
}

export async function combobox(page: Page, label: string): Promise<Locator> {
  const locator = await firstVisible([
    page.getByRole('combobox', { name: label }),
    page.locator(`[aria-label="${label}"]`),
    page.getByText(label, { exact: true }).locator('..').locator('[role="combobox"], button'),
  ]);
  if (!locator) throw new Error(`No dropdown found for "${label}"`);
  return locator;
}

/** Opens a Flutter dropdown by its field label and picks a visible option. */
export async function choose(page: Page, label: string, option: string): Promise<void> {
  await (await combobox(page, label)).click();
  await tap(page, option);
}

export async function toggle(page: Page, label: string): Promise<void> {
  const locator = await firstVisible([
    page.getByRole('checkbox', { name: label }),
    page.getByRole('switch', { name: label }),
    page.getByText(label, { exact: true }),
  ]);
  if (!locator) throw new Error(`No checkbox/switch found for "${label}"`);
  await locator.click();
}

export async function button(page: Page, label: string): Promise<Locator | null> {
  return firstVisible([
    page.getByRole('button', { name: label, exact: true }),
    page.getByRole('button', { name: label }),
    page.locator(`[aria-label="${label}"]`),
    page.getByText(label, { exact: true }),
  ]);
}

export async function tap(page: Page, label: string): Promise<void> {
  const locator = await button(page, label);
  if (!locator) throw new Error(`No visible button/label found for "${label}"`);
  await locator.click();
}

export async function hasLabel(page: Page, label: string): Promise<boolean> {
  return (
    (await page.getByText(label, { exact: true }).count()) > 0 ||
    (await page.locator(`[aria-label="${label}"]`).count()) > 0
  );
}

/** The full menu lives in the end drawer below the NavigationRail breakpoint. */
export async function openDrawer(page: Page): Promise<void> {
  const width = page.viewportSize()?.width ?? 1440;
  if (width >= 1100) return;
  await firstVisible([
    page.getByRole('button', { name: /open (end )?drawer/i }),
    page.locator('[aria-label*="drawer" i]'),
    page.locator('header button').last(),
  ]).then((locator) => locator?.click());
}

/** Clicks a navigation destination instead of using page.goto(). */
export async function navigate(page: Page, label: string): Promise<void> {
  await openDrawer(page);
  await tap(page, label);
  await expect(page.locator('body')).not.toContainText('Something went wrong');
}

/** Clicks the first visible button whose accessible name matches a regex. */
export async function hasButtonMatching(page: Page, pattern: RegExp): Promise<boolean> {
  return (await page.getByRole('button', { name: pattern }).count()) > 0 ||
    (await page.getByText(pattern).count()) > 0;
}

export async function tapMatching(page: Page, pattern: RegExp): Promise<void> {
  const locator = await firstVisible([
    page.getByRole('button', { name: pattern }),
    page.locator('[aria-label]').filter({ hasText: pattern }),
    page.getByText(pattern),
  ]);
  if (!locator) throw new Error(`No button matching ${pattern}`);
  await locator.click();
}

/** The POS discount input has an empty label in lib/features/pos. */
export async function discountField(page: Page): Promise<Locator> {
  const locator = await firstVisible([
    page.getByText('Discount', { exact: true }).locator('..').locator('input'),
    page.locator('input[inputmode="decimal"]').last(),
    page.locator('input').last(),
  ]);
  if (!locator) throw new Error('No discount input found in the POS cart');
  return locator;
}

export function futureDate(days = 180): string {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** Prerequisite fixture: an open cash shift owned by the seeded cashier. */
export async function seedOpenShift(): Promise<string> {
  const email = emailFor('cashier');
  const profiles = await dbRows('profiles', `email=eq.${email}&select=id`);
  expect(profiles.length, 'seeded cashier profile missing').toBe(1);
  const cashierId = String(profiles[0].id);
  const existing = await dbRows(
    'shifts',
    `cashier_id=eq.${cashierId}&status=eq.open&select=id&limit=1`,
  );
  if (existing.length) return String(existing[0].id);
  const created = await api<DbRow[]>('shifts', {
    method: 'POST',
    prefer: 'return=representation',
    body: {
      branch_id: BRANCH_A,
      cashier_id: cashierId,
      opening_cash: 100,
      status: 'open',
    },
  });
  expect(created.status, created.text).toBe(201);
  return String((created.data as DbRow[])[0].id);
}

/** Prerequisite fixture: stock via the same RPC the UI calls. */
export async function seedStock(
  medicineId: string,
  quantity: number,
  batchNo: string,
): Promise<void> {
  const result = await rpc('add_stock_batch', {
    p_branch: BRANCH_A,
    p_medicine: medicineId,
    p_batch_no: batchNo,
    p_expiry: futureDate(),
    p_quantity: quantity,
    p_cost: 2,
  }, await userToken('pharmacist'));
  expect(result.status, `add_stock_batch failed: ${result.text}`).toBe(200);
}

/**
 * Completes a sale through the POS UI (search → tile → cart → payment dialog).
 * Returns the newest sale row from the DB for number-agreement assertions.
 */
export async function sellViaPos(
  page: Page,
  medicineName: string,
  options: { quantity?: number; discount?: number; split?: boolean } = {},
): Promise<DbRow> {
  const quantity = options.quantity ?? 1;
  await navigate(page, NAV.pos);
  const search = await field(page, 'Find medicine by name, SKU or barcode');
  await search.fill(medicineName);
  for (let i = 0; i < quantity; i += 1) {
    await page.getByText(medicineName, { exact: true }).first().click();
  }
  if (options.discount && options.discount > 0) {
    await (await discountField(page)).fill(String(options.discount));
  }
  await capture(page, `pos-cart-${medicineName.replace(/\W+/g, '-')}`);
  await tapMatching(page, /^Pay /);
  if (options.split) {
    await tap(page, 'Add another payment');
    const amounts = page.getByRole('textbox', { name: 'Amount' });
    expect(await amounts.count()).toBeGreaterThanOrEqual(2);
    await amounts.nth(1).fill('10');
    const methods = page.getByRole('combobox', { name: 'Method' });
    if ((await methods.count()) >= 2) {
      await methods.nth(1).click();
      await tap(page, 'Mobile money');
    }
  }
  await tapMatching(page, /^Confirm /);
  await expect(page.getByText(/Sale complete/)).toBeVisible();
  const rows = await dbRows(
    'sales',
    `branch_id=eq.${BRANCH_A}&order=created_at.desc&limit=1&select=id,invoice_no,total,status`,
  );
  expect(rows.length).toBe(1);
  return rows[0];
}

/** Clicks an action icon on the table row containing `rowText`. */
export async function rowAction(page: Page, rowText: string, actionLabel: string): Promise<void> {
  const row = page.locator('tr, [role="row"]').filter({ hasText: rowText }).first();
  expect(await row.count(), `no row containing "${rowText}"`).toBeGreaterThan(0);
  const action = await firstVisible([
    row.getByRole('button', { name: actionLabel }),
    row.locator(`[aria-label="${actionLabel}"]`),
  ]);
  if (!action) throw new Error(`row "${rowText}" has no "${actionLabel}" action`);
  await action.click();
}

export async function assertNoLabel(page: Page, label: string): Promise<void> {
  expect(await hasLabel(page, label), `"${label}" must not be visible`).toBe(false);
}

/** One screenshot per UAT step, plus an annotation that lands in the HTML report. */
export async function capture(page: Page, name: string): Promise<string> {
  const safe = name.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '');
  let project = 'run';
  try {
    project = test.info().project.name;
    test.info().annotations.push({ type: 'uat-step', description: name });
  } catch {
    // capture() is also usable from global helpers outside a test.
  }
  const filename = `${safe}-${project}.png`;
  const dir = path.join(ARTIFACTS, 'screenshots');
  fs.mkdirSync(dir, { recursive: true });
  const filePath = path.join(dir, filename);
  await page.screenshot({ path: filePath, fullPage: true, animations: 'disabled' });
  return filePath;
}

// ---------------------------------------------------------------------------
// PostgREST assertions. Service key = read all state (bypasses RLS); a real
// signed-in user token = assert what that role is actually allowed to see.
// ---------------------------------------------------------------------------

interface ApiResult<T> {
  status: number;
  data: T;
  text: string;
}

export async function api<T = unknown>(
  resource: string,
  options: {
    method?: string;
    body?: unknown;
    token?: string;
    prefer?: string;
  } = {},
): Promise<ApiResult<T>> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${resource}`, {
    method: options.method ?? 'GET',
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${options.token ?? SERVICE_KEY}`,
      'Content-Type': 'application/json',
      ...(options.prefer ? { Prefer: options.prefer } : {}),
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const text = await response.text();
  let data: T;
  try {
    data = text ? (JSON.parse(text) as T) : (undefined as T);
  } catch {
    data = text as T;
  }
  return { status: response.status, data, text };
}

export async function rpc<T = unknown>(
  name: string,
  params: Record<string, unknown>,
  token?: string,
): Promise<ApiResult<T>> {
  return api<T>(`rpc/${name}`, { method: 'POST', body: params, token });
}

export interface DbRow {
  [column: string]: unknown;
}

export async function dbRows(
  table: string,
  query: string,
  token?: string,
): Promise<DbRow[]> {
  const result = await api<DbRow[]>(`${table}?${query}`, { token });
  expect(result.status, `${table} query failed: ${result.text}`).toBe(200);
  return Array.isArray(result.data) ? result.data : [];
}

export async function dbCount(
  table: string,
  query: string,
  token?: string,
): Promise<number> {
  const result = await api<DbRow[]>(`${table}?select=id&${query}`, { token });
  expect(result.status, `${table} count failed: ${result.text}`).toBe(200);
  return Array.isArray(result.data) ? result.data.length : 0;
}

/** Signs in via GoTrue to obtain a real JWT for RLS-sensitive assertions. */
export async function userToken(key: string): Promise<string> {
  const response = await fetch(
    `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: emailFor(key), password: userFor(key).password }),
    },
  );
  const body = (await response.json()) as { access_token?: string; message?: string };
  expect(response.status, `GoTrue sign-in for ${key}: ${JSON.stringify(body)}`).toBe(200);
  expect(body.access_token, `GoTrue returned no access token for ${key}`).toBeTruthy();
  return body.access_token!;
}

/** Reads the session Supabase Flutter persisted in the browser. */
export async function pageToken(page: Page): Promise<string | null> {
  const raw = await page.evaluate(() => {
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i) ?? '';
      const value = localStorage.getItem(key) ?? '';
      if (key.toLowerCase().includes('supabase') && value.includes('access_token')) {
        return value;
      }
    }
    return null;
  });
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as {
      currentSession?: { access_token?: string };
      access_token?: string;
    };
    return parsed.currentSession?.access_token ?? parsed.access_token ?? null;
  } catch {
    return null;
  }
}

export async function assertAccessDenied(page: Page, urlPath: string): Promise<void> {
  await page.goto(urlPath);
  await expect(
    page,
    `${urlPath} must redirect a forbidden role to /forbidden`,
  ).toHaveURL(/\/forbidden$/);
  await expect(page.getByText('Access denied', { exact: true }).first()).toBeVisible();
  await capture(page, `access-denied-${urlPath.replace(/\W+/g, '-')}`);
}

// ---------------------------------------------------------------------------
// Role contract, mirrored from lib/core/permissions.dart (single source of
// truth for what the UI must show and what direct URLs must reject).
// ---------------------------------------------------------------------------

export const NAV = {
  dashboard: 'Dashboard',
  pos: 'New sale',
  inventory: 'Inventory',
  purchasing: 'Purchasing',
  sales: 'Sales history',
  shifts: 'Shifts',
  customers: 'Customers',
  prescriptions: 'Prescriptions',
  suppliers: 'Suppliers',
  expenses: 'Expenses',
  reports: 'Reports',
  users: 'Users and roles',
  team: 'Team access',
  branches: 'Branches',
  settings: 'Settings',
  audit: 'Audit log',
} as const;

export const NAV_BY_ROLE: Record<Role, readonly string[]> = {
  super_admin: Object.values(NAV),
  admin: Object.values(NAV),
  pharmacist: [
    NAV.dashboard,
    NAV.pos,
    NAV.inventory,
    NAV.purchasing,
    NAV.sales,
    NAV.shifts,
    NAV.customers,
    NAV.prescriptions,
    NAV.suppliers,
  ],
  cashier: [
    NAV.dashboard,
    NAV.pos,
    NAV.inventory,
    NAV.sales,
    NAV.shifts,
    NAV.customers,
    NAV.prescriptions,
  ],
  store_keeper: [NAV.dashboard, NAV.inventory, NAV.purchasing, NAV.suppliers],
  accountant: [
    NAV.dashboard,
    NAV.inventory,
    NAV.purchasing,
    NAV.sales,
    NAV.shifts,
    NAV.customers,
    NAV.suppliers,
    NAV.expenses,
    NAV.reports,
  ],
};

/** Walks every permitted nav item through the UI, screenshots each screen. */
export async function walkNav(page: Page, role: Role): Promise<void> {
  for (const label of NAV_BY_ROLE[role]) {
    await navigate(page, label);
    await expect(await hasLabel(page, label), `${role} must reach ${label}`).toBe(true);
    await capture(page, `${role}-nav-${label}`);
  }
}

/** Direct-URL guard checks used by the restricted roles. */
export async function expectForbiddenUrls(page: Page, paths: string[]): Promise<void> {
  for (const urlPath of paths) await assertAccessDenied(page, urlPath);
}
