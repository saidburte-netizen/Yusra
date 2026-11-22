# Yusra Pharmacy UAT journeys

Playwright journeys for all six roles plus one cross-role chain. Every journey
logs in through the real `LoginScreen`, clicks through the real Flutter web
build, and checks both the visible UI and the database through PostgREST.

## Layout

- `bootstrap/start-stack.sh` — starts the Supabase CLI stack, applies the
  idempotent `supabase/all_owner_sql.sql` bundle, serves the admin Edge
  Functions, seeds fixtures and builds/serves Flutter web.
- `bootstrap/seed.sh` — creates branches, one user per role (plus two
  cross-branch users), a supplier, a category and two medicines through
  GoTrue/PostgREST only.
- `bootstrap/env.sh` — reads runtime credentials from `supabase status`. Values
  are exported into the calling shell and are never written to a file or log.
- `bootstrap/run-tests.sh` — re-reads those credentials and runs Playwright.
- `fixtures/uat.ts` — resilient Flutter-web locators, login, DB assertions and
  the per-step screenshot helper.
- `specs/` — one spec per role and `cross_role.spec.ts`.
- `../docs/UAT_*.md` — evidence sheets generated from the final spec line
  numbers. They state exactly which steps were executed here and which remain
  unverified.

## Run locally

Requirements: Docker, Supabase CLI, Flutter 3.24.5, Node 22 and Chromium.

```bash
cd tool/uat
npm ci
npx playwright install --with-deps chromium
cd ../..
bash tool/uat/bootstrap/start-stack.sh
cd tool/uat && npm run test:stack
# later
bash tool/uat/bootstrap/stop-stack.sh
```

CI runs the same commands in `.github/workflows/uat.yml` (job
`UAT journeys (desktop + mobile)`) and uploads screenshots, videos/traces, the
Playwright report and the UAT evidence docs as artifacts.

## Screenshots and evidence

`capture()` writes one full-page screenshot per UAT step into
`tool/uat/artifacts/screenshots/`, with the Playwright project name in the file
name so desktop and mobile evidence cannot overwrite each other. Videos and
traces live under `tool/uat/artifacts/test-results/`. Non-secret run metadata is
in `artifacts/run.json`; keys are deliberately absent.
