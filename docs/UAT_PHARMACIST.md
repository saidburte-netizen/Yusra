# UAT evidence — Pharmacist

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
| `PH-01 sign in and walk every permitted nav item` | `tool/uat/specs/pharmacist.spec.ts:29` | Prescription-first landing (`:32`); all nine permitted nav items (`:37`); Expenses hidden and `/reports`, `/admin/users`, `/expenses` → Access denied (`:40`) | — | `PH-01-landing-<project>.png` (`:35`) |
| `PH-02 catalogue, opening stock without batch/supplier, batches, adjustments, stocktake` | `tool/uat/specs/pharmacist.spec.ts:49` | Create medicine with no supplier (`:54`), category (`:71`), opening stock with blank batch (`:82`), batches + adjustment (`:106`), stocktake variance (`:121`) | `medicines.preferred_supplier_id` null (`:61`), `categories` row (`:77`), generated `stock_batches.batch_no` + `opening` movement (`:91`, `:97`), adjustment movement (`:116`), stocktake movement (`:126`) | `PH-02-medicine-no-supplier`, `PH-02-category`, `PH-02-opening-stock-no-batch`, `PH-02-batches`, `PH-02-adjustment`, `PH-02-stocktake` (`:67`, `:78`, `:102`, `:109`, `:117`, `:127`) |
| `PH-03 prescriptions, Rx dispense, return and void` | `tool/uat/specs/pharmacist.spec.ts:133` | Pharmacist opens own shift from POS (`:136`), registers prescription (`:145`), dispenses Rx-only medicine (`:163`), processes return (`:179`), voids sale (`:191`) | `prescriptions.status = pending` (`:151`), `sales.prescription_id` set (`:171`), `sale_returns` row (`:186`), `sales.status = voided` (`:197`) | `PH-03-shift-open`, `PH-03-prescription`, `PH-03-rx-dispensed`, `PH-03-return`, `PH-03-void` (`:141`, `:157`, `:175`, `:187`, `:199`) |

## Contract discrepancy / unverified

- The requested "pharmacist reports" step conflicts with the authoritative
  permission matrix: `lib/core/permissions.dart` grants pharmacists `_n` for
  `Modules.reports`. The spec therefore asserts `/reports` is **Access denied**
  (`pharmacist.spec.ts:41`) instead of a successful report screen. A product
  decision is required before this can be changed.
- Opening-stock batch generation (`batch_no` generated from a blank field),
  Rx-only POS gating and the return/void dialogs are UI behaviours taken from
  the Dart sources; they were not exercised in Chromium here.
- `seedStock()` uses the same `add_stock_batch` RPC as the UI, with a
  pharmacist-signed JWT, so the prerequisite stock path is real, not SQL.
