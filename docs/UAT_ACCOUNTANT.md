# UAT evidence — Accountant

## Execution contract

- **CI job:** `UAT journeys (desktop + mobile)` in `.github/workflows/uat.yml`.
- **Artifacts:** `uat-screenshots`, `uat-videos-and-traces`,
  `uat-playwright-report`, `uat-docs`.
- **Local verification state:** written, type-checked and listed by Playwright;
  **not executed locally** (no Docker/Supabase CLI in this sandbox). No passing
  claim is made.

## Automated steps

| Test name | Spec location | UI assertion | DB assertion | Screenshot (per project) |
| --- | --- | --- | --- | --- |
| `AC-01 sign in, every nav item, finance-only permissions and direct-URL guards` | `tool/uat/specs/accountant.spec.ts:28` | Dashboard landing + `walkNav('accountant')` (`:33`); Expenses/Reports/Sales/Purchasing visible and POS/prescriptions/admin nav hidden (`:48`); seven direct URLs → Access denied (`:66`) | `profiles.role/branch_id/is_active` for the seeded accountant (`:37`) | `AC-01-dashboard-and-nav`, `AC-01-finance-only-nav` (`:45`, `:63`) |
| `AC-02 expense entry and approval, finance reports, exports and DB agreement` | `tool/uat/specs/accountant.spec.ts:82` | Add expense (`:90`), approve a pending row via row action (`:110`), open Sales/Expenses/Net-profit reports (`:138`), click Export CSV and check operational screens are read-only (`:162`) | `expenses` amount/branch/date (`:99`–`:106`), `status` pending → approved (`:113`–`:134`), `v_report_expenses` month total ≥ both amounts (`:145`–`:150`), `v_report_net_profit` revenue − expenses = net (`:151`–`:159`) | `AC-02-expense-created`, `AC-02-expense-approved`, `AC-02-report-<title>`, `AC-02-expense-export`, `AC-02-operational-readonly` (`:107`, `:135`, `:143`, `:168`, `:174`) |

## Unverified / needs a real run

- Expenses are created as `approved` by the app, so the pending row is seeded
  over PostgREST (`accountant.spec.ts:112`–`:124`) before the UI approval step.
  The `set_expense_status` RPC and the row tooltip must be confirmed in CI.
- `Export CSV` calls the platform share sheet (`Share.share` in
  `lib/core/widgets/data_table_plus.dart`). The spec only asserts that the
  button exists, is clickable and does not produce an error screen; an actual
  downloaded file is not asserted.
- Report views (`v_report_expenses`, `v_report_net_profit`) are queried through
  PostgREST with the service key; RLS with a signed-in accountant token has not
  been exercised here.
