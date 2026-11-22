import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/nav/app_shell.dart';
import '../../../core/permissions.dart';
import '../../../core/state/app_cache.dart';
import '../../../core/supabase_client.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'reorder_models.dart';

final inventoryRepositoryProvider =
    Provider<InventoryRepository>((ref) => InventoryRepository());

/// Branch the current user is allowed to work on. Super admins use the branch
/// selected in the app bar (null means all branches).
final branchScopeProvider = Provider<String?>((ref) {
  final profile = ref.watch(authProvider).profile;
  if (profile == null) return null;
  if (canSeeAllBranches(profile.role)) return ref.watch(selectedBranchProvider);
  return profile.branchId;
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  if (!SupabaseService.isReady) return const <Category>[];
  return ref.read(inventoryRepositoryProvider).categories();
});

final medicinesProvider =
    FutureProvider.family<List<Medicine>, ({String query, String? categoryId})>(
  (ref, filter) async {
    if (!SupabaseService.isReady) return const <Medicine>[];
    return ref
        .read(inventoryRepositoryProvider)
        .medicines(query: filter.query, categoryId: filter.categoryId);
  },
);

final stockSummaryProvider = FutureProvider<List<StockSummary>>((ref) async {
  if (!SupabaseService.isReady) return const <StockSummary>[];
  return ref
      .read(inventoryRepositoryProvider)
      .stockSummary(ref.watch(branchScopeProvider));
});

final lowStockProvider = FutureProvider<List<StockSummary>>((ref) async {
  if (!SupabaseService.isReady) return const <StockSummary>[];
  return ref
      .read(inventoryRepositoryProvider)
      .lowStock(ref.watch(branchScopeProvider));
});

final expiringBatchesProvider = FutureProvider<List<StockBatch>>((ref) async {
  if (!SupabaseService.isReady) return const <StockBatch>[];
  return ref
      .read(inventoryRepositoryProvider)
      .expiringBatches(ref.watch(branchScopeProvider));
});

final batchesProvider =
    FutureProvider.family<List<StockBatch>, String?>((ref, medicineId) async {
  if (!SupabaseService.isReady) return const <StockBatch>[];
  return ref.read(inventoryRepositoryProvider).batches(
        branchId: ref.watch(branchScopeProvider),
        medicineId: medicineId,
      );
});

final movementsProvider = FutureProvider.family<List<StockMovement>,
    ({String? medicineId, String? type})>((ref, filter) async {
  if (!SupabaseService.isReady) return const <StockMovement>[];
  return ref.read(inventoryRepositoryProvider).movements(
        branchId: ref.watch(branchScopeProvider),
        medicineId: filter.medicineId,
        type: filter.type,
      );
});

final reorderSuggestionsProvider =
    FutureProvider.family.autoDispose<List<ReorderSuggestion>, String?>(
  (ref, branchId) async =>
      ref.read(inventoryRepositoryProvider).reorderSuggestions(branchId),
);

/// `expiry_alert_days` from app_settings, with the seeded default of 90.
final expiryAlertDaysProvider = FutureProvider<int>((ref) async {
  if (!SupabaseService.isReady) return 90;
  final key = AppCache.scopedKey(CacheTag.settings, 'global', 'expiry_days');
  return ref.read(appCacheProvider).read(key, const Duration(minutes: 10),
      () async {
    try {
      final row = await SupabaseService.client
          .from('app_settings')
          .select('value')
          .eq('key', 'expiry_alert_days')
          .maybeSingle();
      final value = row?['value'];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 90;
      return 90;
    } catch (_) {
      // The alert window is a display preference; a failed read falls back to
      // the seeded default so the stock screens remain usable.
      return 90;
    }
  });
});
