import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/customers/data/customers.dart';
import '../../features/dashboard/dashboard_screen.dart'
    show
        dashboardExpectedExpensesProvider,
        dashboardPharmacyValueProvider,
        dashboardRefreshProvider;
import '../../features/inventory/data/drug_status_providers.dart';
import '../../features/inventory/data/inventory_providers.dart';
import '../../features/prescriptions/data/prescriptions.dart';
import '../../features/purchasing/data/purchasing.dart';
import '../../features/sales/data/sales.dart';
import '../../features/sales/screens/sales_screen.dart' show cashiersProvider;
import '../../features/suppliers/data/suppliers.dart';
import '../activity/activity.dart';
import '../nav/app_shell.dart';
import 'app_cache.dart';
import 'cache_policy.dart';
import 'connectivity.dart';
import 'idempotency.dart';

/// Stable names for every write that changes more than one screen. Used as
/// the single source of truth for both the invalidation graph and the
/// idempotency prefix.
abstract final class Mutation {
  static const createSale = 'create_sale';
  static const processSaleReturn = 'process_sale_return';
  static const voidSale = 'void_sale';
  static const receivePurchaseOrder = 'receive_purchase_order';
  static const createDraftPurchaseOrders = 'create_draft_purchase_orders';
  static const addOpeningStock = 'add_opening_stock';
  static const openShift = 'open_shift';
  static const closeShift = 'close_shift';
  static const adjustStock = 'adjust_stock';
  static const saveMedicine = 'save_medicine';
  static const saveCategory = 'save_category';
  static const saveSetting = 'save_setting';
  static const saveCustomer = 'save_customer';
  static const saveSupplier = 'save_supplier';
  static const savePrescription = 'save_prescription';
  static const rowAction = 'row_action';
  static const saveUser = 'save_user';
  static const createExpense = 'create_expense';
  static const deleteExpense = 'delete_expense';
  static const dismissLowStockAlert = 'dismiss_low_stock_alert';
}

typedef InvalidateFn = void Function(ProviderOrFamily provider);

/// All providers that can hold data belonging to the signed-in user. They are
/// invalidated on identity change so no provider carries values across users.
final sessionScopedProviders = <ProviderOrFamily>[
  categoriesProvider,
  medicinesProvider,
  stockSummaryProvider,
  drugStatusProvider,
  lowStockAlertsProvider,
  lowStockProvider,
  expiringBatchesProvider,
  batchesProvider,
  movementsProvider,
  reorderSuggestionsProvider,
  lowStockAlertThresholdProvider,
  expiryAlertDaysProvider,
  settingsVersionProvider,
  receiptSettingsProvider,
  myOpenShiftProvider,
  shiftsProvider,
  salesProvider,
  saleProvider,
  saleItemsProvider,
  salePaymentsProvider,
  saleReturnsProvider,
  purchaseOrdersProvider,
  purchaseOrderProvider,
  purchaseItemsProvider,
  customersProvider,
  customerProvider,
  customerStatsProvider,
  prescriptionsProvider,
  suppliersProvider,
  supplierProvider,
  cashiersProvider,
  activityProvider,
];

/// Subset that depends on the branch currently selected in the top bar.
final branchScopedProviders = <ProviderOrFamily>[
  stockSummaryProvider,
  drugStatusProvider,
  lowStockAlertsProvider,
  lowStockProvider,
  expiringBatchesProvider,
  batchesProvider,
  movementsProvider,
  reorderSuggestionsProvider,
  myOpenShiftProvider,
  shiftsProvider,
  salesProvider,
  saleReturnsProvider,
  purchaseOrdersProvider,
  cashiersProvider,
];

const branchScopedTags = <String>[
  CacheTag.stock,
  CacheTag.sales,
  CacheTag.shifts,
  CacheTag.purchases,
  CacheTag.reports,
];

/// The invalidation graph: which providers must be refreshed after each
/// listed mutation. A mutation never relies on the user reloading a screen.
final mutationDependents = <String, List<ProviderOrFamily>>{
  Mutation.createSale: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    salesProvider,
    saleProvider,
    saleItemsProvider,
    salePaymentsProvider,
    myOpenShiftProvider,
    shiftsProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    batchesProvider,
    lowStockProvider,
    movementsProvider,
    cashiersProvider,
    activityProvider,
  ],
  Mutation.processSaleReturn: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    saleReturnsProvider,
    salesProvider,
    saleProvider,
    saleItemsProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    batchesProvider,
    movementsProvider,
    activityProvider,
  ],
  Mutation.voidSale: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    salesProvider,
    saleProvider,
    saleReturnsProvider,
    myOpenShiftProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    activityProvider,
  ],
  Mutation.receivePurchaseOrder: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    purchaseOrdersProvider,
    purchaseOrderProvider,
    purchaseItemsProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    batchesProvider,
    lowStockProvider,
    movementsProvider,
    reorderSuggestionsProvider,
    activityProvider,
  ],
  Mutation.createDraftPurchaseOrders: <ProviderOrFamily>[
    purchaseOrdersProvider,
    purchaseOrderProvider,
    purchaseItemsProvider,
    reorderSuggestionsProvider,
    activityProvider,
  ],
  Mutation.addOpeningStock: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    batchesProvider,
    lowStockProvider,
    expiringBatchesProvider,
    movementsProvider,
    medicinesProvider,
    reorderSuggestionsProvider,
    activityProvider,
  ],
  Mutation.openShift: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    myOpenShiftProvider,
    shiftsProvider,
    activityProvider,
  ],
  Mutation.closeShift: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    myOpenShiftProvider,
    shiftsProvider,
    activityProvider,
  ],
  Mutation.adjustStock: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    batchesProvider,
    lowStockProvider,
    expiringBatchesProvider,
    movementsProvider,
    activityProvider,
  ],
  Mutation.saveMedicine: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    medicinesProvider,
    categoriesProvider,
    stockSummaryProvider,
    drugStatusProvider,
    lowStockAlertsProvider,
    activityProvider,
  ],
  Mutation.saveCategory: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    categoriesProvider,
    medicinesProvider,
    activityProvider,
  ],
  Mutation.saveSetting: <ProviderOrFamily>[
    receiptSettingsProvider,
    lowStockAlertThresholdProvider,
    drugStatusProvider,
    expiryAlertDaysProvider,
    settingsVersionProvider,
    activityProvider,
  ],
  Mutation.saveCustomer: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    customersProvider,
    customerProvider,
    customerStatsProvider,
    activityProvider,
  ],
  Mutation.saveSupplier: <ProviderOrFamily>[
    suppliersProvider,
    supplierProvider,
    activityProvider,
  ],
  Mutation.savePrescription: <ProviderOrFamily>[
    prescriptionsProvider,
    activityProvider,
  ],
  Mutation.rowAction: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    activityProvider,
    medicinesProvider,
    categoriesProvider,
    suppliersProvider,
    customersProvider,
    purchaseOrdersProvider,
    salesProvider,
    shiftsProvider,
  ],
  Mutation.saveUser: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    cashiersProvider,
    activityProvider,
  ],
  Mutation.createExpense: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    activityProvider,
  ],
  Mutation.deleteExpense: <ProviderOrFamily>[
    dashboardRefreshProvider,
    dashboardPharmacyValueProvider,
    dashboardExpectedExpensesProvider,
    activityProvider,
  ],
  Mutation.dismissLowStockAlert: <ProviderOrFamily>[
    lowStockAlertsProvider,
    drugStatusProvider,
    activityProvider,
  ],
};

/// Cache groups dropped by each mutation. Catalogue is invalidated only by
/// catalogue writes; ledger tags are never served from a persisted snapshot.
final mutationCacheTags = <String, Set<String>>{
  Mutation.createSale: <String>{CacheTag.sales, CacheTag.stock},
  Mutation.processSaleReturn: <String>{CacheTag.sales, CacheTag.stock},
  Mutation.voidSale: <String>{CacheTag.sales, CacheTag.stock},
  Mutation.receivePurchaseOrder: <String>{CacheTag.purchases, CacheTag.stock},
  Mutation.createDraftPurchaseOrders: <String>{CacheTag.purchases},
  Mutation.addOpeningStock: <String>{CacheTag.stock, CacheTag.catalogue},
  Mutation.openShift: <String>{CacheTag.shifts},
  Mutation.closeShift: <String>{CacheTag.shifts},
  Mutation.adjustStock: <String>{CacheTag.stock},
  Mutation.saveMedicine: <String>{CacheTag.catalogue},
  Mutation.saveCategory: <String>{CacheTag.catalogue},
  Mutation.saveSetting: <String>{CacheTag.settings},
  Mutation.saveCustomer: <String>{CacheTag.customers},
  Mutation.saveSupplier: <String>{CacheTag.customers},
  Mutation.savePrescription: <String>{CacheTag.prescriptions},
  Mutation.rowAction: <String>{CacheTag.catalogue, CacheTag.reports},
  Mutation.dismissLowStockAlert: <String>{CacheTag.stock},
  Mutation.saveUser: <String>{CacheTag.users, CacheTag.reports},
  Mutation.createExpense: <String>{CacheTag.reports},
  Mutation.deleteExpense: <String>{CacheTag.reports},
};

/// Applies the graph through any invalidate function. Keeping this a free
/// function makes it usable from `Ref`, `WidgetRef`, `ProviderContainer` and
/// unit tests without depending on a widget.
void refreshAfterMutation(InvalidateFn invalidate, String mutation) {
  for (final provider
      in mutationDependents[mutation] ?? const <ProviderOrFamily>[]) {
    if (provider == dashboardRefreshProvider) continue;
    invalidate(provider);
  }
}

/// Providers invalidated when connectivity returns. Ledgers are always fresh,
/// so a dropout must not leave a stale snapshot on screen after reconnect.
void refreshAfterReconnect(InvalidateFn invalidate) {
  for (final provider in sessionScopedProviders) {
    invalidate(provider);
  }
}

/// Drops the cache groups affected by [mutation] through a [Ref]. Kept
/// separate from the provider graph so tests can assert both halves.
void clearMutationCache(Ref ref, String mutation) {
  final tags = mutationCacheTags[mutation];
  if (tags != null) ref.read(appCacheProvider).invalidateAll(tags);
}

void _bumpDashboardIfNeeded(dynamic ref, String mutation) {
  final deps = mutationDependents[mutation] ?? const <ProviderOrFamily>[];
  if (deps.contains(dashboardRefreshProvider)) {
    try {
      final n = (ref as dynamic).read(dashboardRefreshProvider);
      (ref as dynamic).read(dashboardRefreshProvider.notifier).state = n + 1;
    } catch (_) {}
  }
}

extension RefInvalidationGraph on Ref {
  /// Call once after a successful write: refreshes every dependent provider
  /// and drops the affected cache groups — no manual reload required.
  void applyMutation(String mutation) {
    clearMutationCache(this, mutation);
    refreshAfterMutation(invalidate, mutation);
    _bumpDashboardIfNeeded(this, mutation);
  }
}

extension WidgetRefInvalidationGraph on WidgetRef {
  void applyMutation(String mutation) {
    read(appCacheProvider)
        .invalidateAll(mutationCacheTags[mutation] ?? const <String>{});
    refreshAfterMutation(invalidate, mutation);
    _bumpDashboardIfNeeded(this, mutation);
  }
}

/// Session/branch boundaries. Used by `main()` and by `SessionScope`.
abstract final class SessionReset {
  /// Identity changed (sign-in, sign-out, profile refresh that changes role or
  /// branch). Clears every user-scoped provider, the in-memory cache, the
  /// persisted catalogue snapshot and idempotency keys.
  static void onIdentityChanged(ProviderContainer container) {
    // Clear memory and the persisted snapshot before touching providers, so
    // a rebuild triggered by invalidation cannot re-seed the old user's data.
    container.read(appCacheProvider).clear();
    WriteIdempotency.reset();
    container.read(selectedBranchProvider.notifier).state = null;
    container.read(branchSelectionSetProvider.notifier).state = false;
    for (final provider in sessionScopedProviders) {
      container.invalidate(provider);
    }
  }

  /// The super admin switched branch in the top bar. Branch-scoped providers
  /// are reset and cached ledger data for the old branch is dropped.
  static void onBranchChanged(ProviderContainer container) {
    container.read(appCacheProvider).invalidateAll(branchScopedTags);
    for (final provider in branchScopedProviders) {
      container.invalidate(provider);
    }
  }
}

/// Runs a guarded write: offline check -> idempotency -> action -> graph.
/// Repositories hold one of these (created from their provider `ref`).
class WriteCoordinator {
  const WriteCoordinator({this.invalidate, this.clearCache});

  final InvalidateFn? invalidate;
  final void Function(String mutation)? clearCache;

  Future<T> run<T>({
    required String operation,
    required String key,
    required Future<T> Function() action,
  }) async {
    OfflineWriteGuard.ensureOnline();
    return WriteIdempotency.run(
        key: key,
        action: () async {
          final result = await action();
          final inv = invalidate;
          if (inv != null) {
            clearCache?.call(operation);
            refreshAfterMutation(inv, operation);
          }
          return result;
        });
  }
}

final writeCoordinatorProvider = Provider<WriteCoordinator>((ref) {
  return WriteCoordinator(
    invalidate: ref.invalidate,
    clearCache: (mutation) => clearMutationCache(ref, mutation),
  );
});
