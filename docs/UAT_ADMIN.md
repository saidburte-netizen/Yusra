# UAT evidence — Admin (branch-scoped)

## Execution contract

- **CI job:** `UAT journeys (desktop + mobile)` in `.github/workflows/uat.yml`.
- **Artifacts:** `uat-screenshots`, `uat-videos-and-traces`,
  `uat-playwright-report`, `uat-docs`.
- **Local verification state:** written, type-checked and listed by Playwright;
  **not executed locally** (no Docker/Supabase CLI in this sandbox). No passing
  claim is made.
- **Role contract:** `lib/core/permissions.dart` — admin sees all 16 nav items
  but cannot grant `super_admin`, cannot edit other branches, and has no
  branch switcher.

## Automated steps

| Test name | Spec location | UI assertion | DB assertion | Screenshot (per project) |
| --- | --- | --- | --- | --- |
| `AD-01 sign in, full nav, no super-admin creation, no cross-branch edits` | `tool/uat/specs/admin.spec.ts:23` | Dashboard landing + `walkNav('admin')` (`:28`); Create-user role/branch dropdowns hide Super admin and Branch B (`:34`); Add branch / Share my access / Edit role buttons absent (`:51`) | Active branch-A profiles (`:31`); zero `super_admin` profiles created by the UI (`:47`); branch B admin row unchanged (`:62`) | `AD-01-create-user-guard`, `AD-01-branches-readonly`, `AD-01-team-readonly`, `AD-01-cross-branch-unchanged` (`:44`, `:54`, `:57`, `:68`) |
| `AD-02 daily work inside the own branch: catalogue, settings, reports` | `tool/uat/specs/admin.spec.ts:73` | Add category and medicine with no preferred supplier (`:78`); receipt footer + reports + dashboard (`:105`); no branch switcher (`:118`) | `categories` row (`:85`), `medicines.preferred_supplier_id IS NULL` (`:96`), branch-A `sales` count (`:113`) | `AD-02-medicine-no-supplier`, `AD-02-dashboard`, `AD-02-no-branch-switcher` (`:102`, `:115`, `:121`) |

## Unverified / needs a real run

- Flutter dropdown semantics for the role/branch guard step (`:34`) have not
  been rendered; `fixtures/uat.ts:combobox()` falls back to text labels.
- The "create medicine without supplier" path is derived from
  `lib/features/inventory`, but the actual form has not been submitted here.
- RLS enforcement for the cross-branch admin is checked through the service
  role only; a signed-in cross-branch token check is not part of this spec.
  `users.json` seeds that second admin for CI.
