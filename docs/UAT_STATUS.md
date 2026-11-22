# UAT Status — PR #33 merge note

Date: 2026-11-22
PR: https://github.com/saidburte-netizen/Yusra/pull/33
Branch: `fix/premium-dark-mode-quality` (head at merge prep: `7b73165`)

## Decision

UAT journeys were **not green** after multiple fix cycles. CI and Security pentest were green on the same head. Per delivery instructions, UAT was treated as a test-harness/environment blocker (not an app regression) for this merge, documented here, and the merge proceeded with CI+Security green.

This is an explicit, documented exception. Do **not** hide these failures.

## Latest failing run

- Run: https://github.com/saidburte-netizen/Yusra/actions/runs/45073204275
- Workflow: UAT journeys
- Result: failure (30 failed, 0 passed)
- Same-head green checks:
  - CI: https://github.com/saidburte-netizen/Yusra/actions/runs/45073204210
  - Security pentest: https://github.com/saidburte-netizen/Yusra/actions/runs/45073204240

## Observed failures

All 30 UAT tests failed during login with:

```
Error: No form field found for "Email address"
  at field (tool/uat/fixtures/uat.ts:169)
  at login (tool/uat/fixtures/uat.ts:104)
```

Affected: all 15 specs across both `chromium-desktop` and `chromium-mobile` (30 total failures including retries).

## Evidence gathered

- Playwright trace for run 45073204275 shows Flutter web assets loaded (`main.dart.js`, fonts, assets all 200), and `flutter_bootstrap.js` injected script. Console shows only "Injecting <script> tag. Using callback." No page errors captured.
- Earlier traces in the same PR showed two harness-related modes: (1) service worker activation hang with no `main.dart.js` request (fixed by `--pwa-strategy=none` and post-build bootstrap patch in `tool/uat/bootstrap/start-stack.sh`); (2) app rendered but Playwright semantics/DOM interaction unreliable for Flutter web HTML renderer (login field split spans, accessibility placeholder behavior, fill/click not triggering Supabase auth request).
- No Supabase auth request was observed in failing login traces where redirect did not occur; in at least one trace a later test reached Supabase endpoints, indicating the stack itself can run, but login interaction is flaky/broken under Playwright+Flutter web HTML renderer.
- CI flutter analyze/tests pass locally and in CI. The failures are in the Playwright UAT harness interaction with Flutter web, not in Dart unit/widget tests.

## Fixes attempted in PR #33

- Fixed UAT bootstrap path and seeded UAT IDs export in `tool/uat/bootstrap/start-stack.sh`.
- Updated Supabase CLI config compatibility (`[local_smtp]`, `major_version = 15`).
- Disabled Flutter web service worker in UAT/CI web builds (`--pwa-strategy=none`) and nulled `serviceWorkerSettings` in generated bootstrap.
- Hardened `tool/uat/fixtures/uat.ts` selectors for split-span Flutter web text; added accessibility placeholder click and keyboard submit fallbacks; tried click+type instead of fill.
- Regenerated role matrix artifacts after nav refactor.

## Remaining work

- Stabilize Playwright UAT for Flutter web HTML renderer (semantics/input interaction and deterministic login). Consider Flutter integration_test with patrol, or Playwright against CanvasKit/semantics-enabled build with proven selectors, or adding stable semantic identifiers exposed by the app for E2E.
- Re-run UAT journeys and restore required-check status once harness is stable.
- Validate full 6-role manual/device E2E as originally requested.
