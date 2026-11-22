# State Management, Error Handling, and Cache

Branch: `audit/full-system-wiring` (Workstream 4). Owned files only; no SQL, CI workflow, e2e, or other workstream files changed.

## 1. Session / Branch / Identity Boundaries

- **Sign-out clears every provider and persisted cache.** `SessionReset.onIdentityChanged` (`lib/core/state/invalidation.dart`) clears `AppCache` memory + persisted snapshot store, resets `WriteIdempotency`, resets branch selection, and invalidates every provider in `sessionScopedProviders`. `main.dart` listens to auth identity key and calls it on any identity change (sign-in, sign-out, role/branch/active change).
- **Branch switch resets branch-scoped providers.** `SessionReset.onBranchChanged` invalidates `branchScopedProviders` and drops branch ledger cache tags (`stock/sales/shifts/purchases/reports`). `main.dart` listens to `selectedBranchProvider`.
- **No provider holds data across users.** Identity key includes user id, role, branch, active flag (`main.dart:_identityKey`). Cache keys are namespaced through `AppCache.scopedKey(tag, scope, suffix)` (`lib/core/state/app_cache.dart`).
- **Expired session routes to login.** `AuthController._loadProfile` maps `AppError.isSessionExpired` to `AuthState.expired` (`lib/core/auth/auth_controller.dart`). `redirectFor` sends expired sessions to `/login` (`lib/core/router.dart`). `AppErrorMapper` detects JWT/token-expired/auth-401/PGRST301 cases and emits `AUTH_EXPIRED` (`lib/core/errors/app_error.dart`).

## 2. Invalidation Graph (no manual reload)

Defined in `lib/core/state/invalidation.dart` as `mutationDependents` and `mutationCacheTags`. After every listed mutation, the coordinator/UI calls `refreshAfterMutation`/`applyMutation`, which invalidates dependent providers and affected cache tags.

| Mutation | Key dependents refreshed |
|---|---|
| `create_sale` | sales, sale detail/items/payments, myOpenShift/shifts, stock summary/batches/low stock/movements, cashiers, activity |
| `process_sale_return` | saleReturns, sales, sale detail/items, stock summary/batches/movements, activity |
| `receive_purchase_order` | purchaseOrders/order/items, stock summary/batches/low stock/movements, reorder suggestions, activity |
| `create_draft_purchase_orders` | purchaseOrders/order/items, reorder suggestions, activity |
| `add_opening_stock` | stock summary/batches/low/expiring/movements, medicines, reorder suggestions, activity |
| `open_shift` / `close_shift` | myOpenShift, shifts, activity |
| `adjust_stock` | stock summary/batches/low/expiring/movements, activity |

Proof: `test/state/invalidation_graph_test.dart` (`Mutation invalidation graph > refreshAfterMutation invalidates dependents (no manual reload)`) overrides dependents in a `ProviderContainer`, reads them, applies mutation, and asserts recomputation.

## 3. AppError Pipeline

Single mapping boundary: `AppErrorMapper.from` (`lib/core/errors/app_error.dart`). All screens should render mapped errors (existing `AsyncStateView`/`InlineErrorBanner` already use it). Mapping coverage:

- Network/socket/timeout -> `AppErrorKind.network`, retryable, codes `NETWORK`/`TIMEOUT`.
- Offline write guard -> `OfflineException` mapped to `OFFLINE`, retryable.
- Auth expired/JWT expired/401/PGRST301 -> `AUTH_EXPIRED`, routes to login.
- Auth invalid credentials / rate limit -> friendly auth message.
- 42501 / permission -> permission, not retryable.
- PostgREST PGRST* / 23xxx / 22xxx / P000x / 42xxx / 5xx -> friendly text + short whitelisted code line.
- Unknown -> `S.somethingWrong`; raw SQL/PII never surfaced by mapper.
- Duplicate submit -> `DUPLICATE` validation error.

Global boundary: `AppErrorReporter.install()` (`lib/core/errors/error_reporter.dart`) logs only `kind:code` (`sanitizedLogLine`), no PII/raw exception text/stack. Fatal widget boundary renders branded fallback.

## 4. Retry / Error UX

- `AsyncStateView` and `ErrorState` provide retry affordance (`lib/core/state/async_state_view.dart`, `lib/core/widgets/feedback.dart`).
- `InlineErrorBanner` for recoverable section failures.
- Existing screens already pass `onRetry: () => ref.invalidate(...)` / `ref.refresh(...)` widely; WS4 did not rewrite every screen, but core state view and key mutation screens are wired. Remaining screen-level retry gaps should be addressed per screen (see Gaps).

## 5. Double-submit / Idempotency

`lib/core/state/idempotency.dart`: session-scoped key registry. `WriteIdempotency.run` rejects concurrent same-key submits (`DuplicateSubmitException`) and replays completed same-key result within session.

`WriteCoordinator` (`lib/core/state/invalidation.dart`) enforces offline check + idempotency + invalidation graph for repository writes.

Applied keys/guards:
- `create_sale` - POS generates sale key, passes to `SalesRepository.createSale`, resets on success (`lib/features/pos/screens/pos_screen.dart`, `lib/features/sales/data/sales.dart`).
- `receive_purchase_order` - PO screen key + button disabled while busy/offline (`lib/features/purchasing/screens/purchase_order_screen.dart`, `lib/features/purchasing/data/purchasing.dart`).
- `process_sale_return` - sale detail key, reset on success (`lib/features/sales/screens/sale_detail_screen.dart`, `lib/features/sales/data/sales.dart`).
- `add_opening_stock` - opening stock screen key, reset on success (`lib/features/inventory/screens/opening_stock_screen.dart`, `lib/features/inventory/data/inventory_repository.dart`).
- `create_draft_purchase_orders` - needs ordering screen key, reset on success (`lib/features/inventory/screens/needs_ordering_screen.dart`, `lib/features/inventory/data/inventory_repository.dart`).

**Server-side caveat:** current SQL RPCs do not accept idempotency tokens; protection is session-scoped/client-scoped. A true cross-restart guarantee needs a DB migration adding idempotency keys/unique constraints (out of scope for WS4).

## 6. Cache Policy

`lib/core/state/cache_policy.dart`, `lib/core/state/app_cache.dart`.

- **Catalogue (medicines/categories):** stale-while-revalidate. TTL 6h, stale window 7d. Persisted snapshot in SharedPreferences (`SharedPrefsCacheSnapshotStore`), seeded before first frame (`main.dart`), revalidated in background. Snapshot cleared on sign-out.
- **Stock/sales/shifts/reports:** always fresh, no persisted snapshot. Pull-to-refresh / Try again / reconnect invalidation refreshes them.
- **Branding/settings:** cached with version check. `settingsVersionProvider` polls `app_settings.updated_at` max (1 min cache) and invalidates settings tag on change; `receiptSettingsProvider` and `expiryAlertDaysProvider` use `readVersioned`.
- **Offline banner:** global `OfflineBanner` in `app.dart` builder; `OfflineScope` keeps `OfflineWriteGuard` in sync and invalidates session providers on reconnect.
- **Write actions disabled offline:** `writeEnabled(ref)` + `OfflineWriteGuard.ensureOnline()` in coordinator. Key mutation screens disable submit buttons while offline. Not every write button in the app was changed (see Gaps).

## 7. Tests Added

- `test/state/invalidation_graph_test.dart`
  - required mutations present in graph
  - key dependents included for listed mutations
  - refreshAfterMutation invalidates dependents (no manual reload) via ProviderContainer overrides
  - branch switch resets branch-scoped providers
  - sign-out clears cache/idempotency/providers
  - TTL expiry, SWR stale-return/background-refresh, persisted snapshot clear on logout
  - offlineFrom/OfflineWriteGuard behavior, reconnect refresh invalidation
  - idempotency replay and concurrent duplicate rejection

## 8. Remaining Gaps (file:line, reason)

- **Server-side idempotency tokens not implemented.** `lib/core/state/idempotency.dart` is session-scoped only; RPCs in `supabase/migrations/*` do not accept idempotency keys. Fix requires SQL migration + RPC signature changes (out of WS4 scope / SQL ownership).
- **Not all write buttons are disabled offline.** Key required flows guarded: POS pay (`lib/features/pos/screens/pos_screen.dart:998` area), receive PO (`lib/features/purchasing/screens/purchase_order_screen.dart:656` area), returns (`lib/features/sales/screens/sale_detail_screen.dart:384` area), opening stock (`lib/features/inventory/screens/opening_stock_screen.dart:474` area), create draft POs (`lib/features/inventory/screens/needs_ordering_screen.dart:584` area). Other writes (settings save, user create, category/medicine save, adjustments, expenses, prescriptions, etc.) still rely on coordinator/network error; adding `writeEnabled` everywhere is low-risk but broad UI churn - document rather than over-touching unowned-risk screens.
- **Cache persisted snapshot is catalogue-only and coarse.** `lib/core/state/cache_policy.dart` stores unfiltered medicines/categories JSON; filtered medicine queries are memory-cached only. This is intentional to avoid stale partial snapshots.
- **POS held cart is already persisted locally** via `HeldCartStore` (`lib/features/sales/logic/held_carts.dart`) and draft cart persistence in POS screen; WS4 did not change this behavior. Offline writes are blocked, but cart draft survives restart.
- **Retry coverage not uniform on every list/detail screen.** `AsyncStateView`/`ErrorState` provide retry; many screens already pass `onRetry`, but a full audit of every screen is beyond safe WS4 patch size. Core infrastructure is in place.
- **Reconnect refresh invalidates all session-scoped providers.** `refreshAfterReconnect` in `lib/core/state/invalidation.dart` is intentionally broad; may cause extra refetches but avoids stale ledgers. Can be narrowed by tag/visibility later.
- **AppErrorMapper still has some unmapped domain cases as friendly generic text.** It covers required codes/classes; rare PostgREST codes fall back to generic server message with code line when code is whitelisted. Further per-code tuning needs evidence from production logs.
