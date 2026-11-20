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
    admin/               users, branches, settings, audit log
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
  migrations/            numbered SQL record of the owner's applied steps, plus
                         proposed 0012/0013 hardening and RPC gaps
  checks/                schema_check.sql
  functions/             Edge Functions for admin user management
tool/                    seed_demo.dart, smoke_test.dart
docs/                    database.md, test-plan.md
```

State management is Riverpod, navigation is go_router, and the backend is
Supabase (Postgres, Auth, Storage and Edge Functions). **All stock and money
changes go through database RPCs** (`create_sale`, `void_sale`,
`process_sale_return`, `receive_purchase_order`, `adjust_stock`, `open_shift`,
`close_shift`, …). The app never writes `stock_batches`, `sales`, `sale_items`,
`sale_payments`, `shifts` or `sale_returns` directly.

Roles and the permission matrix are documented in `docs/database.md`.

## 1. Create the Supabase project

1. Create a Supabase project and copy its **URL** and **anon key** from
   Project Settings → API.
2. In the SQL Editor, run the migration files in `supabase/migrations/` in
   filename order, one file per query. See `supabase/README.md` for the
   details, the already-applied status and the change protocol.
3. Run `supabase/checks/schema_check.sql`. It must report no `MISSING` rows.
4. Replace `PUT-THE-EMAIL-HERE` in `0011_seed.sql` (or run the equivalent
   `UPDATE profiles SET role = 'admin' WHERE email = ...` after the first
   user signs up).
5. Review and run `0012_rls_hardening.sql` and `0013_rpc_gaps.sql`, then run
   the smoke test below.

## 2. Create the first super admin

Sign up the first user in the app (or via Supabase Auth), then run in the SQL
Editor:

```sql
update profiles
set role = 'super_admin', is_active = true
where email = 'you@example.com';
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

1. Java 17, Flutter stable (pinned to 3.24.5), Android SDK 34, build-tools
   34.0.0, `flutter doctor -v`.
2. `flutter pub get`, `flutter analyze`, `flutter test`.
3. `flutter build apk --release` and `flutter build web --release`.
4. Uploads both artifacts.

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
`docs/test-plan.md` for the full manual test plan and `docs/database.md` for
the schema and permission matrix.
