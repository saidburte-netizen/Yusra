import { defineConfig, devices } from '@playwright/test';

/**
 * Yusra Pharmacy UAT — Playwright configuration.
 *
 * The journeys are browser-only: they log in through the real LoginScreen and
 * click through the real Flutter web build. Every step is also asserted against
 * PostgREST (service role for state, signed-in user token for RLS checks).
 *
 * Flutter web accessibility note
 * ------------------------------
 * Flutter renders a semantics tree into the DOM only when the browser asks for
 * accessibility. Chromium is therefore launched with
 * `--force-renderer-accessibility`, and the web build is produced with
 * `--web-renderer html` by bootstrap/start-stack.sh. Locators go through the
 * resilient helpers in fixtures/uat.ts rather than raw CSS wherever possible.
 */

const webUrl = process.env.UAT_WEB_URL ?? 'http://127.0.0.1:4173';

export default defineConfig({
  testDir: './specs',
  outputDir: 'artifacts/test-results',
  // Journeys share one seeded database (shifts, stock and finance totals), so
  // they must be serialised to keep the cross-role number assertions exact.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  timeout: 120_000,
  expect: { timeout: 20_000 },
  globalSetup: './bootstrap/global-setup.ts',
  reporter: [
    ['list'],
    ['html', { outputFolder: 'artifacts/playwright-report', open: 'never' }],
    ['json', { outputFile: 'artifacts/results.json' }],
  ],
  use: {
    baseURL: webUrl,
    trace: 'on-first-retry',
    video: 'on',
    screenshot: 'off', // per-step screenshots are taken explicitly by capture()
    launchOptions: {
      args: [
        '--force-renderer-accessibility',
        '--disable-dev-shm-usage',
        '--no-sandbox',
      ],
    },
  },
  webServer: {
    command: 'node bootstrap/serve-web.mjs',
    url: webUrl,
    reuseExistingServer: true,
    timeout: 60_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
  projects: [
    {
      name: 'chromium-desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1440, height: 900 },
      },
    },
    {
      name: 'chromium-mobile',
      use: {
        ...devices['Pixel 7'],
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
        deviceScaleFactor: 2,
      },
    },
  ],
});
