# CI/CD — Yusra Pharmacy

This document is the operating manual for the GitHub Actions setup. The source
of truth for the pinned toolchain and the PR gate is
`.github/workflows/ci.yml`; this file documents it and the three new files
added alongside it:

| File | Role |
| --- | --- |
| `.github/workflows/ci.yml` | Required PR/push gate: toolchain, format/analyze/test, DB checks, e2e-api, optional smoke, gated Edge Function deploy. **Owned by another workstream — do not edit here.** |
| `.github/workflows/release.yml` | Tag `vX.Y.Z`: validate migrations from scratch twice, build signed APK + web zip, publish a GitHub Release with a changelog; manual-only live migration apply behind an approval environment; gated Edge Function deploy. |
| `.github/workflows/web-deploy.yml` | Build web with an explicit `--base-href`, upload the artifact, remind about Supabase redirect URLs, gated static-host deploy. |
| `.github/dependabot.yml` | Weekly `pub`, `npm`, `github-actions` and `docker` update PRs. |

No workflow reads, prints or stores a service-role key. The app is built with
`SUPABASE_URL` / `SUPABASE_ANON_KEY` only (`lib/core/env.dart:1-12`); the
service-role key belongs exclusively to the Edge Function environment
(`supabase/functions/admin-create-user/index.ts:1-2`).

---

## 1. Required PR checks (and what is cached)

`CI` runs on every push and every pull request, on all branches
(`ci.yml:3-10`). All of the jobs below are mandatory except the two explicitly
marked optional. The gate job is `toolchain` (STEP 0) and it asserts the exact
versions before anything else runs (`ci.yml:35-154`).

| Required check (job name shown on the PR) | What it proves | Cache in place today |
| --- | --- | --- |
| `STEP 0 — install and print toolchain versions` | Flutter 3.24.5, Dart 3, Java 17, Gradle 8.3, Android SDK 34 / build-tools 34.0.0, Deno, Node 20, Playwright 1.48.2, Supabase CLI, PostgreSQL 16, Docker, PostgREST v12.2.3 are all installed and printed (`ci.yml:35-154`). | Flutter SDK + pub cache via `subosito/flutter-action@v2` `cache: true` (`ci.yml:72-78`); Gradle distribution/dependency cache via `gradle/actions/setup-gradle@v4` (`ci.yml:90-91`). |
| `Analyze, test, build APK and web` | `flutter pub get`, `dart format --set-exit-if-changed .`, `deno check` on both functions, `flutter analyze`, `flutter test --exclude-tags e2e-api`, release APK and web builds, both artifacts uploaded (`ci.yml:156-329`). | Same Flutter/pub and Gradle caches as above. |
| `Postgres schema and migration checks` | `all_owner_sql.sql` applied twice (idempotency), numbered migrations in order, `schema_check.sql` and `tool/db_test.sql` with zero FAIL rows on PostgreSQL 16 (`ci.yml:331-443`). | PostgreSQL comes from a `postgres:16` service container (`ci.yml:340-353`) — no SQL cache needed. The matching `psql` client runs inside the image via `tool/ci_psql.sh`. |
| `End-to-end API tests (PostgreSQL 16 + PostgREST)` | Real HTTP against real repositories through PostgREST v12.2.3 with signed JWTs (`ci.yml:500-583`). | Docker pulls `postgrest/postgrest:v12.2.3` on every run (`ci.yml:139-142,552`). |
| `Deploy Supabase Edge Functions` | Deploy both functions from `main` when `SUPABASE_ACCESS_TOKEN` + `SUPABASE_PROJECT_REF` exist; a no-op otherwise (`ci.yml:585-627`). | Supabase CLI installed fresh (`supabase/setup-cli@v1`). |

Optional, never blocking on missing secrets: `Manual Supabase smoke test`
(only on `workflow_dispatch` with `run_smoke`, `ci.yml:445-498`).

**Caching gaps to close in `ci.yml` (requires the owning workstream):**

- Add `actions/cache@v4` for `~/.pub-cache` keyed on `pubspec.lock` if a faster
  cold start is wanted beyond what `flutter-action` already does.
- Cache the Playwright browser download (`~/.cache/ms-playwright`) keyed on the
  pinned `1.48.2` version — currently reinstalled with `--with-deps` each run
  (`ci.yml:112-113`).
- Cache the PostgREST Docker image at the runner level or pin a pre-baked
  image; `docker pull` runs on every toolchain and e2e job.
- No cache exists for the Supabase CLI binary.

`dart_test.yaml` keeps the PostgREST suite tagged so the unit job excludes it
and the `e2e-api` job runs it deliberately (`ci.yml:269-273,578-579`).

---

## 2. Release workflow — tag `vX.Y.Z`

`.github/workflows/release.yml` triggers on `push` tags matching `v*.*.*` and on
manual dispatch. The tag is validated as `X.Y.Z` before any build
(`release.yml`, "Resolve version and build number").

Jobs:

1. **`validate-migrations`** — starts the local Supabase stack from
   `supabase/config.toml` (PostgreSQL 16 at `config.toml:18`), runs
   `supabase db reset --yes` **twice** (each reset drops and recreates the
   database and re-applies every numbered migration from scratch), and after
   each pass runs `supabase db lint --local`, `schema_check.sql` and
   `db_test.sql`, failing on any `FAIL` row. Needs no secrets or token.
2. **`release`** (tag pushes only) — sets up the same pinned toolchain as CI,
   runs format/analyze/tests and `deno check`, builds and uploads:
   - `yusra-pharmacy-apk-<version>.apk` — signed when all four signing secrets
     (`ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
     `KEY_PASSWORD`) exist; falls back to the debug key with a warning when
     they do not. `android/app/build.gradle:42-57` reads `android/key.properties`
     written by the workflow; a partial signing configuration fails loudly.
   - `yusra-pharmacy-web-<version>.zip` — built with the correct `--base-href`
     (repository variable `WEB_BASE_HREF`, default `/`).
   - A `CHANGELOG.md` generated from `git log` between the previous tag and
     this one (`fetch-depth: 0` supplies tags; no explicit `git fetch` is
     needed).
   Both artifacts and the changelog are attached to the GitHub Release via
   `softprops/action-gh-release@v2`. That is the only step needing a token; it
   uses the automatic `GITHUB_TOKEN` with `contents: write` granted to the job
   — **no user-managed secret is read or echoed**.

### Automatic build-number bump

`pubspec.yaml:4` still reads `version: 1.0.0+1`, and
`android/app/build.gradle:38-39` maps `versionCode`/`versionName` straight from
Flutter. The release workflow bumps both at build time without editing source:

```
name   = tag without the leading v          (1.2.3)
number = ${{ github.run_number }}           (monotonically increasing)
flutter build apk --release --build-name="$name" --build-number="$number" ...
flutter build web --release --build-name="$name" --build-number="$number" ...
```

Both `--build-number` and `--build-name` are supported by Flutter 3.24.5 for
APK and web. Never bump the checked-in `pubspec.yaml` build number in a release
commit: the workflow value wins and a source edit would drift out of sync.

---

## 3. Web deploy workflow

`.github/workflows/web-deploy.yml` runs on manual dispatch and when a GitHub
Release is published.

- **Base href.** Manual dispatch takes a `base_href` input (default `/`); a
  release run uses repository variable `WEB_BASE_HREF` (default `/`). The value
  is validated to start **and** end with `/` before being passed to
  `flutter build web --base-href=...`. A domain-root host (Firebase Hosting,
  `yusra-pharmacy.web.app`) uses `/`; a GitHub Pages project site would use
  `/<repo-name>/`. `web/index.html:17` contains the
  `$FLUTTER_BASE_HREF` placeholder that this flag replaces — not editing the
  file and relying on the default is the common cause of a blank deployed page
  with 404 asset requests.
- **Artifact.** The whole `build/web/` folder is uploaded as
  `yusra-pharmacy-web` and can be deployed manually from any green run.
- **Supabase redirect URLs (important).** The printed notice is a real
  deployment step, not decoration: after deploying, add the exact origin
  (for example `https://yusra-pharmacy.web.app` and the same with a trailing
  `/`) under **Supabase → Authentication → URL Configuration → Redirect
  URLs**, set **Site URL** to that origin, and keep
  `supabase/config.toml:37-38` (`site_url`, `additional_redirect_urls`) in sync.
  Password resets (`lib/core/auth/auth_controller.dart:222-231`) and any
  future OAuth flow fail at runtime if this is skipped. The repository default
  `https://yusra-pharmacy.web.app` is already present at `config.toml:38`;
  override it with `vars.WEB_PUBLIC_ORIGIN` for a custom domain.
- **Gated host deploy.** The `deploy-host` job only runs on manual dispatch
  with `publish_deploy` and when both `secrets.FIREBASE_TOKEN` and
  `vars.FIREBASE_PROJECT_ID` are set; otherwise it warns and is a no-op. It
  deploys the downloaded artifact with Firebase Hosting. No token is printed.

---

## 4. Edge Function deploy (gated on secrets)

The app calls two privileged functions: `admin-create-user` and
`admin-reset-password` (`lib/features/admin/users_screen.dart`). They read
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` and
`APP_ORIGIN` from the **Function** environment, not from GitHub
(`README.md` "Owner manual actions", item 4).

Deployment is duplicated in two places, both gated:

- CI: `ci.yml:585-627`, on pushes to `main` only, checking
  `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` before installing the CLI
  and deploying each function; absent secrets make the job a no-op.
- Release: `release.yml` `deploy-edge-functions` job, same gate, so a tagged
  release can publish the functions the shipped app expects.

Both functions are type-checked with `deno check` in `ci.yml:261-265` and in the
release build. The Edge Functions must be deployed before user create/reset
password works; the UI shows the deploy command on a 404/network error
(`docs/SCREEN_MATRIX.md:58-61`).

---

## 5. Database migration job

### Validation (automatic, secretless)

`release.yml` `validate-migrations` runs on every tag and every dispatch:

1. `supabase start` — real local stack from `supabase/config.toml`, PostgreSQL
   16 per `config.toml:15-18`.
2. For `pass` in `1 2`: `supabase db reset --yes`, then `supabase db lint
   --local`, then `supabase db execute --local --file
   supabase/checks/schema_check.sql` and `... tool/db_test.sql`; grep for
   `FAIL`, fail on any match. Two resets mean the whole migration set is
   proven installable **from scratch twice**, not just incrementally.
3. `supabase stop --no-backup` always runs in cleanup.

This is complementary to CI's `db-test` job, which uses a plain `postgres:16`
service plus `tool/supabase_stubs.sql` to apply `all_owner_sql.sql` twice
(`ci.yml:392-412`). The local-stack validation is intentionally not in
`ci.yml` because that file is owned by another workstream — see gaps.

### Apply to the live project (manual, approval-gated)

`release.yml` `apply-migrations-live`:

- `if: github.event_name == 'workflow_dispatch' && inputs.apply_migrations` —
  it **never** runs on a tag push.
- `environment: name: production-approval` — configure this Environment in
  **Settings → Environments** with at least one required reviewer and, ideally,
  a branch policy limited to `main`. The run pauses until a reviewer approves.
- Checks `SUPABASE_ACCESS_TOKEN` + `SUPABASE_PROJECT_REF`; if either is absent
  it warns and skips (a fresh repository stays green).
- Runs `supabase db push --linked --dry-run --project-ref <ref>` first for a
  visible list of pending migrations, then `supabase db push --linked
  --project-ref <ref>`. `db push` applies only pending migrations in filename
  order; it never re-runs old ones.

Apply order for an existing project that predates this workflow is documented
in `docs/database.md:5-13` and `README.md` "Owner manual actions": a fresh
project can have all migrations applied, but an existing project that already
has `0001`–`0018` must only receive the newer files (from `0019` onward).

---

## 6. Rollback notes

There are **no down migrations**. Plan to recover, not to "undo":

1. **Before any live apply**, take a database backup (Supabase Dashboard →
   Database → Backups, or `supabase db dump --linked --project-ref <ref> >
   backup.sql`). Keep it outside the repository. Point-in-Time Recovery is the
   last resort for a destructive change; note that not all plans include it.
2. **Migration failed mid-way:** the failed migration is recorded in
   `supabase_migrations.schema_migrations`. Fix the SQL in a **new** numbered
   migration (never edit an applied one), validate it with the two-reset job,
   then apply the fix. Manual `delete` from `schema_migrations` to force a retry
   is a break-glass action only and must be reviewed.
3. **Bad release, database unchanged:** redeploy the previous web artifact or
   the previous tag's APK; both are retained for 30 days as Actions artifacts
   and attached to their GitHub Releases. Do not re-tag an old commit — create
   a new release tag so build numbers keep increasing.
4. **Bad release + bad migration:** restore the pre-apply backup (or PITR,
   before accepting logins again), then redeploy the previous artifacts. The
   activity log and audit log are append-only and must be preserved; do not
   truncate them as part of a rollback.
5. **Local development:** `supabase db reset` is the complete local rollback —
   it discards local data and reapplies all migrations. Nothing here touches
   the live project.
6. **Auth/storage config** (redirect URLs, function secrets, bucket policies)
   is not in migrations; record the previous values before changing them. The
   replace functions in `0019_hardening_fixes.sql` are idempotent but re-apply
   only what changed.

---

## 7. Dependabot

`.github/dependabot.yml` schedules weekly updates (Mondays 06:00
Africa/Addis_Ababa) for four ecosystems, each limited to 5 open PRs and using
its own commit prefix:

| Ecosystem | Directory | Status |
| --- | --- | --- |
| `pub` | `/` | Active — `pubspec.yaml` / `pubspec.lock`. |
| `github-actions` | `/` | Active — keeps `actions/checkout@v4`, `subosito/flutter-action@v2`, `gradle/actions/setup-gradle@v4`, `supabase/setup-cli@v1`, `softprops/action-gh-release@v2`, etc. current. |
| `npm` | `/` | Configured, inert until a `package.json` is committed (e.g. to pin the Playwright version used by `ci.yml:112`). |
| `docker` | `/` | Configured, inert until a `Dockerfile`/compose file is committed (e.g. for a local PostgREST image). |

Every Dependabot PR must pass the same required checks as a human PR. Because
`flutter-action` and `setup-gradle` are version-sensitive, review pub and
actions bumps together when they touch the Flutter 3.24.5 / Gradle 8.3 / AGP
8.1.0 compatibility set documented at `pubspec.yaml:39-44`.

---

## 8. Branch-protection checklist

Configure **Settings → Branches → Branch protection rules** for `main`:

- [ ] **Require a pull request before merging**, with at least 1 approving
      review; dismiss stale approvals when new commits are pushed.
- [ ] **Require status checks to pass** and **require branches to be up to date
      before merging**. Select exactly these check names from `ci.yml`:
      - `STEP 0 — install and print toolchain versions`
      - `Analyze, test, build APK and web`
      - `Postgres schema and migration checks`
      - `End-to-end API tests (PostgreSQL 16 + PostgREST)`
      Do **not** require `Manual Supabase smoke test` or
      `Deploy Supabase Edge Functions` (both are conditional/no-op jobs).
- [ ] **Require conversation resolution** before merging.
- [ ] **Block force pushes** and **block deletions** of `main`.
- [ ] **Do not allow bypassing** the above settings, including for admins.
- [ ] **Require signed commits** (recommended) and linear history
      (squash or rebase) so the changelog generator produces readable entries.
- [ ] Add a separate **Environment** `production-approval` with required
      reviewers; this is what gates `apply-migrations-live` in `release.yml`.
- [ ] Limit who can create `v*.*.*` tags to release owners, and limit who can
      run `workflow_dispatch` on `release.yml` / `web-deploy.yml`.
- [ ] Keep `CI` as the only required workflow on PRs; release and deploy runs
      must not be PR requirements.

---

## 9. Gaps needing `ci.yml` or code changes

These are intentionally **not** fixed by this workstream because the files are
owned elsewhere:

1. **`ci.yml`:** add the local-Supabase "reset twice" validation as a PR check
   (today it only runs on release/dispatch). CI's `db-test` uses plain Postgres
   plus stubs (`ci.yml:331-443`), so a migration that depends on real Auth or
   Storage objects is not caught until release time.
2. **`ci.yml`:** add explicit caches for Playwright browsers, the Supabase CLI
   and the PostgREST Docker image (see §1).
3. **Code:** the expenses flow has no repository/provider layer and reports
   have two parallel definitions (`reports_screen.dart:46` vs
   `reports.dart:25`); the dashboard reads base tables instead of the
   `v_report_*` views and has no return/void or expense tile. See
   `docs/CONNECTIVITY.md`, "Cross-cutting observations".
4. **Repository:** add a `package.json` and a `Dockerfile` to activate the npm
   and docker Dependabot entries; otherwise they are harmless no-ops.
5. **Repository settings (not code):** configure the
   `production-approval` environment with reviewers, set `WEB_BASE_HREF` /
   `WEB_PUBLIC_ORIGIN` / `FIREBASE_PROJECT_ID` variables, and add the signing
   and Supabase deploy secrets. None of these are printed or stored by the
   workflows.
