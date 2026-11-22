# UAT evidence — Super admin

## Execution contract

- **CI job:** `UAT journeys (desktop + mobile)` in `.github/workflows/uat.yml`
  (workflow `UAT journeys`). Both `chromium-desktop` and `chromium-mobile`
  projects run every test below.
- **Artifacts:** `uat-screenshots`, `uat-videos-and-traces`,
  `uat-playwright-report`, `uat-docs`.
- **Local verification state:** the specs are written, type-checked with
  `npx tsc --noEmit -p tool/uat/tsconfig.json`, and listed with
  `npm run list` (30 tests in 7 files). **No journey was executed locally**
  because Docker and the Supabase CLI are unavailable in this sandbox. Nothing
  in this document should be read as a passing-test claim.
- **Stack bootstrap:** `tool/uat/bootstrap/start-stack.sh` starts the real
  Supabase CLI stack, reapplies `supabase/all_owner_sql.sql`, serves the admin
  Edge Functions, seeds users/fixtures via GoTrue + PostgREST, and builds/serves
  Flutter web. Credentials are read from `supabase status` at runtime by
  `tool/uat/bootstrap/env.sh`; they are never printed or stored.

## Automated steps

| Test name | Spec location | UI assertion | DB assertion | Screenshot (per project) |
| --- | --- | --- | --- | --- |
| `SA-01 sign in, every nav item at both viewports, DB role check` | `tool/uat/specs/super_admin.spec.ts:48` | Dashboard landing + all-branch switcher (`super_admin.spec.ts:53`); all 16 nav destinations via `walkNav()` (`super_admin.spec.ts:60`) | One active profile per role in `profiles` (`super_admin.spec.ts:64`) | `SA-01-dashboard-<project>.png`, `SA-01-db-profiles-<project>.png` (`:57`, `:71`) |
| `SA-02 branches, all role users, role/branch change, deactivate/reactivate` | `tool/uat/specs/super_admin.spec.ts:76` | Create branch (`:81`), create six role users through the Edge Function dialog (`:94`), change role/branch (`:111`), deactivate/reactivate (`:123`), switch branch (`:133`) | `branches` row (`:90`), `profiles` row per created user (`:106`), changed `role`/`branch_id` (`:117`), `is_active` false then true (`:126`, `:129`) | `SA-02-branch-created`, `SA-02-user-<role>`, `SA-02-role-branch-changed`, `SA-02-deactivated`, `SA-02-reactivated`, `SA-02-branch-switched` (`:91`, `:107`, `:120`, `:127`, `:130`, `:139`) |
| `SA-03 settings, correction approval, all reports and live dashboard` | `tool/uat/specs/super_admin.spec.ts:144` | Publish receipt footer (`:149`), approve a pending correction (`:160`), open all 12 reports (`:173`), dashboard counters (`:184`) | `app_settings.value` (`:155`), `activity_log.approved_by` + `correction_requested=false` (`:164`), all 12 report views queryable via PostgREST (`:180`), `sales` count (`:188`) | `SA-03-settings`, `SA-03-correction-approved`, `SA-03-report-<title>`, `SA-03-dashboard` (`:157`, `:170`, `:178`, `:190`) |

## Unverified / needs a real run

- GoTrue user creation through the `admin-create-user` Edge Function and the
  "Temporary password" dialog rely on Flutter web accessibility labels; the
  dialog was not rendered here.
- The 12 report titles and view names (`v_report_sales_payment`,
  `v_report_purchases_supplier`) were aligned with
  `lib/features/reports/data/reports.dart`, but the report screen itself was
  not opened in a browser.
- Whether `supabase functions serve` is reachable from the Flutter web build at
  the same origin is a CI-runtime question; the workflow starts it before the
  build (`:50`–`:59` of `start-stack.sh`).
- Cross-branch visibility for a super admin is asserted only through UI and
  DB state; it has not been observed at runtime.
