# UAT evidence — Cashier

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
| `CA-01 sign in, nav walk, hidden and direct-URL forbidden areas` | `tool/uat/specs/cashier.spec.ts:30` | POS landing + `walkNav('cashier')` (`:33`); no Needs ordering / branch switcher (`:39`); nine forbidden nav labels hidden (`:47`); 11 direct URLs → Access denied (`:64`) | Signed-in cashier token sees only branch-A `sales` (`:78`–`:85`) | `CA-01-inventory-no-needs-ordering`, `CA-01-forbidden-nav-hidden` (`:44`, `:61`) |
| `CA-02 shift, discounts, split payment, hold/resume, Rx block, receipt, close` | `tool/uat/specs/cashier.spec.ts:89` | Open shift (`:94`), quick customer (`:104`), within-limit discount + split payment (`:115`), over-limit discount rejected (`:143`), hold/resume (`:155`), Rx-only blocked (`:169`), close shift (`:181`) | `shifts` open row (`:100`), `customers` row (`:111`), `sale.discount > 0` + two `sale_payments` (`:134`–`:139`), no Confirm after rejected discount (`:151`), "Select a prescription…" blocker (`:177`), closed shift opening 100 / closing 110 (`:186`–`:189`) | `CA-02-shift-open`, `CA-02-customer-added`, `CA-02-split-sale-receipt`, `CA-02-discount-limit`, `CA-02-hold-resume`, `CA-02-rx-blocked`, `CA-02-shift-closed` (`:101`, `:112`, `:140`, `:152`, `:166`, `:178`, `:190`) |

## Unverified / needs a real run

- The POS cart search, discount field (which is unlabelled in
  `lib/features/pos`), split-payment dialog and receipt banner are located
  through `fixtures/uat.ts` fallbacks. Flutter web semantics must be checked in
  the CI browser run.
- The Z-report expectation `closing_cash = 110` assumes the shift-close dialog
  accepts the counted amount verbatim; this has not been observed here.
- Direct `/inventory/opening-stock` denial depends on the router guard reading
  `permissions.dart`; the guard itself was not executed locally.
