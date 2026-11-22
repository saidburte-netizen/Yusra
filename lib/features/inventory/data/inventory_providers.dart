import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/nav/app_shell.dart';
import '../../../core/permissions.dart';
import '../../../core/state/app_cache.dart';
import '../../../core/state/cache_policy.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'reorder_models.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(coordinator: ref.read(writeCoordinatorProvider));
});

/// Branch the current user is allowed to work on. Super admins use the branch
/// selected in the app bar (null means all branches).
final branchScopeProvider = Provider<String?>((ref) {
  final profile = ref.watch(authProvider).profile;
  if (profile == null) return null;
  if (canSeeAllBranches(profile.role)) return ref.watch(selectedBranchProvider);
  return profile.branchId;
});

/// Catalogue cache keys. Kept in one place so a persisted snapshot can seed
/// the exact entry a provider will read after a cold start.
String categoriesCacheKey() =>
    AppCache.scopedKey(CacheTag.catalogue, 'global', 'categories');

String medicinesCacheKey(String query, String? categoryId) =>
    AppCache.scopedKey(
        CacheTag.catalogue, 'global', 'medicines:$query:${categoryId ?? ''}');

/// Seeds the in-memory cache from the persisted catalogue snapshot so the app
/// can render a catalogue immediately and revalidate in the background.
Future<void> restoreCatalogueSnapshot(
  AppCache cache,
  SharedPrefsCacheSnapshotStore? store,
) async {
  if (store == null) return;
  final entries = store.read();

  final rawMedicines = entries['medicines'];
  if (rawMedicines != null) {
    try {
      final decoded = jsonDecode(rawMedicines) as List;
      final medicines = decoded
          .map(
              (row) => Medicine.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      cache.restore(medicinesCacheKey('', null), medicines,
          age: CachePolicy.catalogueTtl);
    } catch (_) {
      // A corrupt snapshot is ignored; the network loader repopulates it.
    }
  }

  final rawCategories = entries['categories'];
  if (rawCategories != null) {
    try {
      final decoded = jsonDecode(rawCategories) as List;
      final categories = decoded
          .map(
              (row) => Category.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      cache.restore(categoriesCacheKey(), categories,
          age: CachePolicy.catalogueTtl);
    } catch (_) {
      // Same as above: never let disk data break a screen.
    }
  }
}

Future<void> _saveCatalogue(
    Ref ref, Map<String, String> Function(Map<String, String>) update) async {
  final store = ref.read(cacheSnapshotStoreProvider);
  if (store == null) return;
  await store.save(update(store.read()));
}

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  if (!SupabaseService.isReady) return const <Category>[];
  return ref.read(appCacheProvider).readSWR<List<Category>>(
        categoriesCacheKey(),
        CachePolicy.catalogueTtl,
        () => ref.read(inventoryRepositoryProvider).categories(),
        staleFor: CachePolicy.catalogueStale,
        onLoaded: (items) => _saveCatalogue(ref, (entries) {
          entries['categories'] = jsonEncode(items
              .map((item) => <String, dynamic>{
                    'id': item.id,
                    'name': item.name,
                    'description': item.description,
                    'is_active': item.isActive,
                  })
              .toList());
          return entries;
        }),
      );
});

final medicinesProvider =
    FutureProvider.family<List<Medicine>, ({String query, String? categoryId})>(
  (ref, filter) async {
    if (!SupabaseService.isReady) return const <Medicine>[];
    return ref.read(appCacheProvider).readSWR<List<Medicine>>(
          medicinesCacheKey(filter.query, filter.categoryId),
          CachePolicy.catalogueTtl,
          () => ref
              .read(inventoryRepositoryProvider)
              .medicines(query: filter.query, categoryId: filter.categoryId),
          staleFor: CachePolicy.catalogueStale,
          // Only the unfiltered catalogue is a complete snapshot.
          onLoaded: (filter.query.isEmpty && filter.categoryId == null)
              ? (items) => _saveCatalogue(ref, (entries) {
                    entries['medicines'] = jsonEncode(items
                        .map((item) => <String, dynamic>{
                              'id': item.id,
                              ...item.toJson(),
                            })
                        .toList());
                    return entries;
                  })
              : null,
        );
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
  return ref.read(appCacheProvider).readVersioned<int>(
    key,
    CachePolicy.settingsTtl,
    () => ref.read(settingsVersionProvider.future),
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
        // The alert window is a display preference; a failed read falls
        // back to the seeded default so stock screens remain usable.
        return 90;
      }
    },
  );
});
