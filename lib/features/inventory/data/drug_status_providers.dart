import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import 'inventory_models.dart';
import 'inventory_providers.dart';

/// Live status for the drug-stock grid. Quantities come from v_stock_summary,
/// whose available_qty is the unexpired batch balance after sales, returns and
/// voids. Target comes from the catalogue target_level (or 2× reorder level).
class DrugStatusItem {
  const DrugStatusItem({
    required this.medicine,
    required this.availableQty,
    required this.threshold,
    required this.targetLevel,
    required this.suggestedOrderQty,
    required this.supplierId,
    required this.lastPurchaseCost,
  });

  final Medicine medicine;
  final int availableQty;
  final int threshold;
  final int targetLevel;
  final int suggestedOrderQty;
  final String? supplierId;
  final double lastPurchaseCost;

  bool get isOut => availableQty <= 0;
  bool get isLow => !isOut && availableQty < threshold;
  String get statusLabel => isOut ? 'Out' : isLow ? 'Low' : 'In stock';
}

const _catalogueFilter = (query: '', categoryId: null);

final lowStockAlertThresholdProvider = FutureProvider<int>((ref) async {
  if (!SupabaseService.isReady) return 5;
  try {
    final row = await SupabaseService.client
        .from('app_settings')
        .select('value')
        .eq('key', 'low_stock_alert_threshold')
        .maybeSingle();
    final raw = row?['value'];
    final parsed = switch (raw) {
      num value => value.toInt(),
      String value => int.tryParse(value),
      Map<String, dynamic> value => switch (value['value']) {
          num nested => nested.toInt(),
          String nested => int.tryParse(nested),
          _ => null,
        },
      _ => null,
    };
    if (parsed == null || parsed < 0) return 5;
    return parsed;
  } catch (_) {
    return 5;
  }
});

final drugStatusProvider = FutureProvider<List<DrugStatusItem>>((ref) async {
  if (!SupabaseService.isReady) return const <DrugStatusItem>[];
  final branchId = ref.watch(branchScopeProvider);
  final summaries = await ref.watch(stockSummaryProvider.future);
  final medicines = await ref.watch(medicinesProvider(_catalogueFilter).future);
  final suggestions =
      await ref.watch(reorderSuggestionsProvider(branchId).future);
  final threshold = await ref.watch(lowStockAlertThresholdProvider.future);

  // A super admin with no branch selected sees one card per medicine, so
  // quantities and suggestions are summed across branches.
  final availableByMedicine = <String, int>{};
  for (final row in summaries) {
    if (row.medicineId.isEmpty) continue;
    availableByMedicine[row.medicineId] = (availableByMedicine[row.medicineId] ?? 0) +
        row.availableQty;
  }
  final suggestedByMedicine = <String, int>{};
  final supplierByMedicine = <String, String?>{};
  final costByMedicine = <String, double>{};
  for (final row in suggestions) {
    suggestedByMedicine[row.medicineId] =
        (suggestedByMedicine[row.medicineId] ?? 0) + row.suggestedOrderQty;
    supplierByMedicine[row.medicineId] ??= row.preferredSupplierId;
    costByMedicine[row.medicineId] ??= row.lastPurchaseCost;
  }

  final items = <DrugStatusItem>[];
  for (final medicine in medicines) {
    final available = availableByMedicine[medicine.id];
    if (available == null) continue;
    final target = medicine.targetLevel ?? medicine.reorderLevel * 2;
    items.add(
      DrugStatusItem(
        medicine: medicine,
        availableQty: available,
        threshold: threshold,
        targetLevel: target > 0 ? target : 1,
        suggestedOrderQty: suggestedByMedicine[medicine.id] ??
            (target - available).clamp(1, 9999),
        supplierId: supplierByMedicine[medicine.id] ??
            medicine.preferredSupplierId,
        lastPurchaseCost: costByMedicine[medicine.id] ?? medicine.costPrice,
      ),
    );
  }
  items.sort((a, b) => a.availableQty.compareTo(b.availableQty));
  return items;
});

class LowStockAlert {
  const LowStockAlert({
    required this.medicineId,
    required this.branchId,
    required this.name,
    required this.availableQty,
    required this.qtyAtDismiss,
  });

  final String medicineId;
  final String branchId;
  final String name;
  final int availableQty;
  final int? qtyAtDismiss;
}

final lowStockAlertsProvider = FutureProvider<List<LowStockAlert>>((ref) async {
  if (!SupabaseService.isReady) return const <LowStockAlert>[];
  final branchId = ref.watch(branchScopeProvider);
  var query = SupabaseService.client.from('v_low_stock_alerts').select();
  if (branchId != null) query = query.eq('branch_id', branchId);
  final rows = await query.order('available_qty') as List;
  return rows.map((raw) {
    final row = raw as Map;
    return LowStockAlert(
      medicineId: row['medicine_id'] as String? ?? '',
      branchId: row['branch_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      availableQty: intValue(row['available_qty']),
      qtyAtDismiss: row['qty_at_dismiss'] == null
          ? null
          : intValue(row['qty_at_dismiss']),
    );
  }).toList();
});

final lowStockAlertCountProvider = Provider<int>((ref) {
  return ref.watch(lowStockAlertsProvider).valueOrNull?.length ?? 0;
});

/// Keeps stock-derived screens and the bell count live across devices.
/// Watched once from AppShell so it does not depend on the open screen.
final stockAlertRealtimeProvider = Provider<void>((ref) {
  if (!SupabaseService.isReady) return;
  final client = SupabaseService.client;
  void invalidateStock() {
    for (final provider in <ProviderOrFamily>[
      stockSummaryProvider,
      lowStockProvider,
      batchesProvider,
      movementsProvider,
      reorderSuggestionsProvider,
      drugStatusProvider,
      lowStockAlertsProvider,
    ]) {
      ref.invalidate(provider);
    }
  }

  final channel = client.channel('yusra-stock-status');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'stock_batches',
        callback: (_) => invalidateStock(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        callback: (_) => invalidateStock(),
      )
      .subscribe();
  ref.onDispose(() => client.removeChannel(channel));
});
