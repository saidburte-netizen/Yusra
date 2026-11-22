# UAT evidence — Cross-role chain

## Execution contract

- **CI job:** `UAT journeys (desktop + mobile)` in `.github/workflows/uat.yml`.
- **Artifacts:** `uat-screenshots`, `uat-videos-and-traces`,
  `uat-playwright-report`, `uat-docs`.
- **Local verification state:** the spec is written, type-checked and listed by
  Playwright; **not executed locally** (no Docker/Supabase CLI in this sandbox).
  No passing claim is made.
- **One test, six signed-in roles:** `withRole()` opens a fresh browser context
  and logs in through the real `LoginScreen` for each role in turn.

## Automated steps

| Test name | Spec location | UI assertion | DB / number assertion | Screenshot (per project) |
| --- | --- | --- | --- | --- |
| `XR-01 PO → stock → sale → finance → admin → correction with reconciled numbers` | `tool/uat/specs/cross_role.spec.ts:74` | — | Baselines captured at `:81`–`:95` (stock, revenue, expenses, sale count, report-view values) | — |
| ↳ store keeper receives PO | `cross_role.spec.ts:100` | Draft → approve → receive goods with a unique batch (`:102`–`:127`) | PO `draft → ordered → received` (`:112`–`:133`); batch 20 units (`:134`–`:139`); `purchase` movement +20 (`:140`–`:144`); shelf stock = baseline + 20 (`:145`) | `XR-01-po-draft`, `XR-01-po-received` (`:118`, `:146`) |
| ↳ pharmacist sees stock | `cross_role.spec.ts:150` | Batches screen shows the exact batch number (`:152`–`:154`) | Same batch has 20 units and the seeded medicine id (`:155`–`:161`) | `XR-01-pharmacist-stock` (`:162`) |
| ↳ cashier sells 3 units | `cross_role.spec.ts:166` | Shift ensured, three units sold through POS (`:168`–`:170`) | `sale_items` quantity 3, total = lines + VAT (`:171`–`:178`); stock −3 (`:179`); sale movement −3 (`:180`–`:184`); revenue delta = sale total (`:185`–`:188`) | `XR-01-cashier-sale` (`:189`) |
| ↳ accountant records expense | `cross_role.spec.ts:193` | Add expense 11.75, open Net profit statement (`:195`–`:214`) | Expense row (`:202`–`:210`); view revenue delta = sale total, expense delta = 11.75, net = revenue − expenses (`:216`–`:232`); daily sales net delta = sale total (`:233`–`:237`) | `XR-01-accountant-report` (`:215`) |
| ↳ admin sees dashboard/activity | `cross_role.spec.ts:241` | Today's sales on dashboard (`:244`); cashier email in audit table (`:249`) | Sale count = baseline + 1 (`:245`); `activity_log` row for the sale with cashier as actor (`:250`–`:255`) | `XR-01-admin-dashboard`, `XR-01-admin-activity` (`:246`, `:256`) |
| ↳ super admin approves correction | `cross_role.spec.ts:260` | Pending approval filter + Approve correction row action (`:289`–`:291`) | Fresh pending correction seeded via PostgREST (`:265`–`:281`); PO audited (`:282`–`:286`); `correction_requested=false`, `approved_by`/`approved_at` set (`:292`–`:299`); final stock/revenue/expense reconciliation (`:301`–`:305`) | `XR-01-super-admin-correction` (`:306`) |

## Unverified / needs a real run

- The chain depends on real FIFO batch consumption in `create_sale`. All
  number assertions use before/after deltas, so they remain valid whichever
  batch is consumed, but the batch visibility step at `:154` must be confirmed
  in Chromium.
- VAT is read from `app_settings` by the RPC; the spec derives the expected
  total from `sale_items.line_total + tax` instead of hard-coding a rate.
- `activity_log` rows are produced by database triggers; the audit table's
  email/role columns must render the cashier actor for `:249` to pass.
- The workflow serialises all journeys (`workers: 1` in
  `tool/uat/playwright.config.ts`) so the shared shift/stock baseline cannot be
  changed by a parallel spec.
