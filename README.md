# Yusra Pharmacy — Care made easy

Yusra Pharmacy is a full-stack pharmacy control system that combines stock,
purchasing, point of sale, prescriptions, cash shifts, finance and staff
control in one interface. It targets **Android (APK) first**, with a **Flutter
web** build for desktop cashiers and admins.

- Currency: **ETB**. Prices are stored **excluding VAT**; VAT defaults to 15%
  and is configurable in Admin → Settings.
- Stock is counted in **whole units** and consumed **FEFO** (nearest expiry
  first) by the database RPCs, never by the client.
- All dates are shown in **Africa/Addis_Ababa**.
- The UI is English; every user-facing string lives in
  `lib/core/strings.dart` so Amharic can be added later.

## Architecture

```
lib/
  core/                  theme, strings, money/dates, auth, permissions, router,
                         app shell and shared widgets
  features/
    auth/                sign in, forgot password, profile
    dashboard/           role-aware dashboard
    admin/               users, team access sharing, branches, settings, audit log
    inventory/           medicines, categories, batches, adjustments, alerts, stocktake
    suppliers/           supplier directory
    purchasing/          purchase orders, approval, receipt, PDFs
    pos/                 product search, cart, split payments, barcode, receipt printing
    sales/               history, sale detail, voids, returns
    shifts/              X/Z reports and cash reconciliation
    customers/           customer directory and purchase history
    prescriptions/       Rx register, image upload, dispensing link
    expenses/            expense capture and approval
    reports/             sales, stock, finance reports
supabase/
  migrations/            0001–0018 baseline plus new 0019 hardening migration
  checks/                schema_check.sql (through 0019)
  all_owner_sql.sql      full 0001–0019 bundle for fresh / recovery projects
  functions/             Edge Functions for admin user management
tool/                    seed_demo.dart, smoke_test.dart, db_test.sql, CI helpers
docs/                    AUDIT.md, database.md, test-plan.md
```

State management is Riverpod, navigation is go_router, and the backend is
Supabase (Postgres, Auth, Storage and Edge Functions). **All stock and money
changes go through database RPCs** (`create_sale`, `void_sale`,
`process_sale_return`, `receive_purchase_order`, `adjust_stock`, `open_shift`,
`close_shift`, …). The app never writes `stock_batches`, `sales`, `sale_items`,
`sale_payments`, `shifts` or `sale_returns` directly.

Roles and the permission matrix are documented in `docs/database.md`.

Cross-cutting infrastructure lives under `lib/core/errors/` and
`lib/core/state/`: every boundary maps exceptions through `AppErrorMapper`
into one user-facing `AppError` (no raw SDK strings in the UI), a global
`AppErrorReporter` replaces Flutter's red error screen, `AppCache` provides
TTL-based, user-scoped caching with tag invalidation for reference data, and
`AsyncStateView` gives every screen the same loading/error/retry treatment.
The super admin's **Team access** page shares role, branch and published
settings with teammates exclusively through the proposed 0015 RPCs.

## 1. Create the Supabase project

1. Create a Supabase project and copy its **URL** and **anon key** from
   Project Settings → API.
2. **Existing project:** run only the new `supabase/migrations/0019_hardening_fixes.sql`
   and then `supabase/checks/schema_check.sql`. Do **not** re-run `0001`–`0018`.
   **Fresh project:** run `0001`–`0019` in filename order, or run the generated
   `supabase/all_owner_sql.sql` once as a single query; it is re-runnable.
3. `0019` makes `handle_new_user` default new users without role metadata to
   `super_admin`; backfills missing profiles; hardens every SECURITY DEFINER
   function; fixes PO/expense/audit authorization; and adds `customer_stats`,
   `shift_expected_cash`, storage policies and report-view `date` columns.
4. Run `supabase/checks/schema_check.sql`. Every row must be `PASS`; then run
   `tool/db_test.sql` in CI (or locally against PostgreSQL 16) and the smoke
   test below.

## 2. Create the first super admin

After `0019`, the first user created without an `app_metadata.role` receives
`super_admin` automatically. If that account already exists, confirm it with:

```sql
select id, email, role, is_active from public.profiles where email = 'you@example.com';
```

If its role is not `super_admin`, promote it **before creating anyone else**
using Admin → Users, or:

```sql
select public.set_user_access(user_id, 'super_admin', null, true)
from public.profiles where email = 'you@example.com';
```

Use that account in Admin → Users to create the remaining staff. Never commit
a service-role key or a database password to this repository.

## 3. Deploy the Edge Functions

The two functions in `supabase/functions/` create and reset staff users with
the service-role key stored only in Supabase. Deploy them from the Actions tab
(`Deploy Supabase Edge Functions` runs automatically on `main`) or manually:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase functions deploy admin-create-user
supabase functions deploy admin-reset-password
```

## 4. Configure GitHub secrets

Add these under Settings → Secrets and variables → Actions:

| Secret | Required for | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | build, smoke test | Project URL, baked into the APK/web build |
| `SUPABASE_ANON_KEY` | build, smoke test | Public anon key |
| `SUPABASE_ACCESS_TOKEN` | Edge Function deploy | Supabase CLI token |
| `SUPABASE_PROJECT_REF` | Edge Function deploy | Project reference |
| `ANDROID_KEYSTORE_BASE64` | signed APK | Base64 of the release keystore |
| `KEYSTORE_PASSWORD` | signed APK | Keystore password |
| `KEY_ALIAS` | signed APK | Key alias |
| `KEY_PASSWORD` | signed APK | Key password |
| `SMOKE_ADMIN_EMAIL` / `SMOKE_ADMIN_PASSWORD` | smoke test | Admin demo user |
| `SMOKE_CASHIER_EMAIL` / `SMOKE_CASHIER_PASSWORD` | smoke test | Cashier demo user |
| `SMOKE_PHARMACIST_EMAIL` / `SMOKE_PHARMACIST_PASSWORD` | smoke test | Pharmacist demo user |
| `SMOKE_BRANCH_ID` | smoke test | Optional branch id |
| `SMOKE_EXPIRED_BATCH_ID` | smoke test | Optional expired batch printed by the seeder |

The first four deploy secrets are optional: if they are absent the deploy job
is a no-op. The four signing secrets are optional: without them the APK uses
the default debug key. **Never add a service-role key as a GitHub secret for
the app build** — it must never be shipped inside the APK or web bundle.

## 5. Run the Actions workflows

`CI` runs on every push and pull request, on all branches, in this order:

1. Java 17, Flutter stable (pinned to 3.24.5), Dart 3, Android SDK 34,
   build-tools 34.0.0, preinstalled platform-tools, Deno; versions are printed
   and asserted.
2. `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`,
   `flutter test`, `deno check`.
3. `db-test` applies `all_owner_sql.sql` twice and the numbered migrations on
   PostgreSQL 16, then runs `schema_check.sql` and `tool/db_test.sql`.
4. `flutter build apk --release` and `flutter build web --release`; both
   artifacts are uploaded.

Open the Actions tab of a push or PR to see the result. Nothing merges to
`main` unless the run is green.

### Download the artifacts

On a green run, scroll to **Artifacts** at the bottom of the run page:

- `yusra-pharmacy-apk` — download and unzip, then copy `app-release.apk` to an
  Android device and install it.
- `yusra-pharmacy-web` — download and unzip, then serve the folder with any
  static web server.

Artifacts are retained for 30 days.

### Manual smoke test

In the Actions tab choose **CI → Run workflow**. Leave `confirm_prod`
unchecked unless you have deliberately targeted a project whose URL contains
`prod`. The job runs `dart run tool/smoke_test.dart` and fails if any rule is
violated.

## 6. Seed demo data (optional)

```bash
export SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=...
dart run tool/seed_demo.dart
```

This creates one user per role (`@yusra.test`), a main branch, eight
categories, 30 realistic medicines, a supplier and two FEFO batches per
medicine, plus an expired fixture batch. It refuses to run against a URL
containing `prod` unless `SEED_CONFIRM=1`. The service-role key is read from
the environment at runtime and is never written to disk.

## 7. Deploy the web build

After a green `main` run, download `yusra-pharmacy-web` and either:

- enable GitHub Pages from a branch containing the unzipped folder, or
- upload the folder to any static host (Netlify, Cloudflare Pages, S3, nginx).

The web build reads the same `SUPABASE_URL` and `SUPABASE_ANON_KEY` that were
baked in during the build, so no separate configuration is needed.

## Local development

```bash
flutter pub get
flutter analyze
flutter test

flutter run \
  --dart-define=SUPABASE_URL="..." \
  --dart-define=SUPABASE_ANON_KEY="..."
```

Do not commit real keys to `.env` files or source code. See
`docs/AUDIT.md` for the end-to-end wire-check, `docs/test-plan.md` for the
full manual test plan and `docs/database.md` for the schema and permission
matrix.

## Owner manual actions (required after merge)

1. **SQL:** If `0001`–`0018` are already applied, run only
   `supabase/migrations/0019_hardening_fixes.sql`, then
   `supabase/checks/schema_check.sql`. A fresh project can run
   `supabase/all_owner_sql.sql` instead.
2. **Auth:** Disable public Signup in Supabase Auth (the local
   `supabase/config.toml` has `enable_signup = false`), configure the Auth
   redirect URLs for the deployed web origin, and decide the email
   confirmation policy.
3. **Storage:** Verify the `prescriptions`, `receipts`, `branding`, `avatars`
   and `medicine-images` buckets and the `0019` policies. Buckets holding
   receipts/Rx images must stay private; only `branding` and
   `medicine-images` are public.
4. **Edge Functions:** Set `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
   `SUPABASE_ANON_KEY` and `APP_ORIGIN` as Supabase Function secrets, then
   deploy `admin-create-user` and `admin-reset-password`.
5. **GitHub:** Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, optional signing
   secrets, optional deploy secrets and optional `SMOKE_*` secrets. Smoke
   secrets are CI-only and opt-in.
6. **Security:** Rotate any PAT that was previously pasted into chat. It must
   not be reused or printed.
