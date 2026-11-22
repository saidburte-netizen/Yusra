# UAT evidence — Store keeper

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
| `SK-01 sign in, nav walk, no sales or finance access` | `tool/uat/specs/store_keeper.spec.ts:25` | Inventory landing + `walkNav('store_keeper')` (`:28`); no POS/sales/finance labels or New sale button (`:34`); seven direct URLs → Access denied (`:53`) | — | `SK-01-no-sales-finance-<project>.png` (`:50`) |
| `SK-02 suppliers, PO draft/approve/receive, opening stock, adjustments, reorder` | `tool/uat/specs/store_keeper.spec.ts:65` | Supplier (`:70`); PO draft → Approve & send → Receive goods (`:82`); opening stock + adjustment (`:120`); Needs ordering reorder action (`:141`) | `suppliers` row (`:78`); `purchase_orders.status` draft → ordered (`:104`), `stock_batches` + `purchase` movement (`:110`–`:116`); batch by `batch_no` (`:129`), adjustment movement (`:137`); draft PO count does not decrease (`:149`) | `SK-02-supplier`, `SK-02-po-draft`, `SK-02-po-received`, `SK-02-adjustment`, `SK-02-reorder-draft-pos` (`:80`, `:99`, `:117`, `:138`, `:151`) |

## Unverified / needs a real run

- The `receive_purchase_order` RPC and its UI dialog (batch no/expiry) were not
  executed here; the spec mirrors `PurchaseOrderScreen` from the Dart sources.
- The reorder step asserts only that the draft-PO count does not decrease
  (`store_keeper.spec.ts:149`) because the SQL trigger may create zero drafts
  when every medicine is already above its reorder level.
- The same PO flow is exercised again in the cross-role chain with a unique
  batch number so stock numbers can be reconciled.
