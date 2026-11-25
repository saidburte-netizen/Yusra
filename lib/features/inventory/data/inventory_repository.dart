import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/state/idempotency.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import 'inventory_models.dart';
import 'reorder_models.dart';

/// All reads and writes for Agent B. Stock mutations always go through the
/// database RPCs; nothing here updates stock_batches directly.
class InventoryRepository {
  InventoryRepository({WriteCoordinator? coordinator})
      : _coordinator = coordinator ?? const WriteCoordinator();

  final WriteCoordinator _coordinator;

  SupabaseClient get _db => SupabaseService.client;

  Future<List<Category>> categories({bool includeInactive = true}) async {
    var query = _db.from('categories').select();
    if (!includeInactive) query = query.eq('is_active', true);
    final rows = await query.order('name') as List;
    return rows
        .map((row) => Category.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> saveCategory(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await _db.from('categories').insert(data);
    } else {
      await _db.from('categories').update(data).eq('id', id);
    }
  }

  Future<void> setCategoryActive(String id, bool active) =>
      _db.from('categories').update({'is_active': active}).eq('id', id);

  Future<List<Medicine>> medicines({
    String query = '',
    String? categoryId,
    int limit = 200,
  }) async {
    var request = _db.from('medicines').select();
    if (query.trim().isNotEmpty) {
      final q = query.trim().replaceAll(RegExp(r'[,()]'), ' ');
      request = request.or(
          'name.ilike.%$q%,generic_name.ilike.%$q%,barcode.ilike.%$q%,sku.ilike.%$q%');
    }
    if (categoryId != null) request = request.eq('category_id', categoryId);
    final rows = await request.order('name').limit(limit) as List;
    return rows
        .map((row) => Medicine.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Medicine> medicine(String id) {
    return _db
        .from('medicines')
        .select()
        .eq('id', id)
        .single()
        .then((row) => Medicine.fromJson(Map<String, dynamic>.from(row)));
  }

  /// Server-side barcode/SKU lookup used by the POS scanner.
  ///
  /// Both comparisons run in Postgres (not in Dart) so a scanned code finds a
  /// medicine even when the local catalogue page is filtered or paginated.
  /// A partial match is used as a fallback for labels that contain the code
  /// embedded in a longer value.
  Future<Medicine?> findByBarcode(String code) async {
    final value = code.trim();
    if (value.isEmpty) return null;
    final safe = value.replaceAll(RegExp(r'[,()]'), ' ');
    final rows = await _db
        .from('medicines')
        .select()
        .or('barcode.ilike.$safe,sku.ilike.$safe')
        .limit(1) as List;
    if (rows.isNotEmpty) {
      return Medicine.fromJson(Map<String, dynamic>.from(rows.first as Map));
    }
    final partial = await medicines(query: value);
    return partial.isEmpty ? null : partial.first;
  }

  Future<void> saveMedicine(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await _db.from('medicines').insert(data);
    } else {
      await _db.from('medicines').update(data).eq('id', id);
    }
  }

  Future<void> setMedicineActive(String id, bool active) =>
      _db.from('medicines').update({'is_active': active}).eq('id', id);

  /// Byte-based upload: no `dart:io` File is involved, so this is identical on
  /// web and Android. [contentType] comes from the picked XFile when known.
  Future<String> uploadMedicineImage(
    String medicineId,
    Uint8List bytes, {
    String contentType = 'image/png',
  }) async {
    final path = '$medicineId/${DateTime.now().microsecondsSinceEpoch}.img';
    await _db.storage.from('medicine-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return _db.storage.from('medicine-images').getPublicUrl(path);
  }

  Future<List<StockSummary>> stockSummary(String? branchId) async {
    var query = _db.from('v_stock_summary').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('name') as List;
    return rows
        .map((row) =>
            StockSummary.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<StockSummary>> lowStock(String? branchId) async {
    var query = _db.from('v_low_stock').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('available_qty') as List;
    return rows
        .map((row) =>
            StockSummary.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<StockBatch>> expiringBatches(String? branchId) async {
    var query = _db.from('v_expiring_batches').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('expiry_date') as List;
    return rows
        .map(
            (row) => StockBatch.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<StockBatch>> batches({
    required String? branchId,
    String? medicineId,
    bool includeInactive = false,
  }) async {
    var query = _db
        .from('stock_batches')
        .select('*, medicine:medicines!stock_batches_medicine_id_fkey(name)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (medicineId != null) query = query.eq('medicine_id', medicineId);
    if (!includeInactive) query = query.eq('is_active', true);
    final rows = await query.order('expiry_date') as List;
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final joined = map['medicine'] ?? map['medicines'];
      if (joined is Map) map['name'] = joined['name'];
      return StockBatch.fromJson(map);
    }).toList();
  }

  Future<List<StockMovement>> movements({
    required String? branchId,
    String? medicineId,
    String? type,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _db
        .from('stock_movements')
        .select('*, medicine:medicines!stock_movements_medicine_id_fkey(name)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (medicineId != null) query = query.eq('medicine_id', medicineId);
    if (type != null) query = query.eq('movement_type', type);
    if (from != null) query = query.gte('created_at', from.toIso8601String());
    if (to != null) query = query.lte('created_at', to.toIso8601String());
    final rows =
        await query.order('created_at', ascending: false).limit(500) as List;
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final joined = map['medicine'] ?? map['medicines'];
      if (joined is Map) map['name'] = joined['name'];
      return StockMovement.fromJson(map);
    }).toList();
  }

  /// Adds one batch through the 8-argument RPC and returns the stored batch
  /// number (auto-generated when [batchNo] is blank), not the batch id.
  Future<String> addStock({
    required String branchId,
    required String medicineId,
    required String batchNo,
    required DateTime expiry,
    required int quantity,
    required double cost,
    String? supplierId,
    String source = 'opening',
  }) async {
    final result = await _db.rpc('add_stock_batch', params: {
      'p_branch': branchId,
      'p_medicine': medicineId,
      'p_batch_no': batchNo,
      'p_expiry': _date(expiry),
      'p_quantity': quantity,
      'p_cost': cost,
      'p_supplier': supplierId,
      'p_source': source,
    });
    final batchId = result.toString();
    final saved = await _db
        .from('stock_batches')
        .select('batch_no')
        .eq('id', batchId)
        .maybeSingle();
    return (saved?['batch_no'] as String?) ?? batchNo;
  }

  /// Registers several opening-stock rows in one all-or-nothing RPC call.
  Future<int> addOpeningStock({
    required String branchId,
    required List<OpeningStockRowInput> rows,
    String? idempotencyKey,
  }) {
    return _coordinator.run<int>(
      operation: Mutation.addOpeningStock,
      key: idempotencyKey ?? WriteIdempotency.newKey(Mutation.addOpeningStock),
      action: () async {
        final result = await _db.rpc('add_opening_stock', params: {
          'p_branch': branchId,
          'p_rows': rows.map((row) => row.toJson()).toList(),
        });
        return result is num
            ? result.toInt()
            : int.tryParse('$result') ?? rows.length;
      },
    );
  }

  Future<List<ReorderSuggestion>> reorderSuggestions(String? branchId) async {
    var query = _db.from('v_reorder_suggestions').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('name') as List;
    return rows
        .map((row) =>
            ReorderSuggestion.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Creates one draft PO per supplier and returns their ids.
  Future<List<String>> createDraftPurchaseOrders({
    required String branchId,
    required List<Map<String, dynamic>> lines,
    String? idempotencyKey,
  }) {
    return _coordinator.run<List<String>>(
      operation: Mutation.createDraftPurchaseOrders,
      key: idempotencyKey ??
          WriteIdempotency.newKey(Mutation.createDraftPurchaseOrders),
      action: () async {
        final result = await _db.rpc('create_draft_purchase_orders', params: {
          'p_branch': branchId,
          'p_lines': lines,
        });
        if (result is! List) return const <String>[];
        return result.map((id) => id.toString()).toList();
      },
    );
  }

  Future<bool> dismissLowStockAlert({
    required String medicineId,
    required String branchId,
  }) async {
    final result = await _db.rpc('dismiss_low_stock_alert', params: {
      'p_medicine': medicineId,
      'p_branch': branchId,
    });
    return result == true;
  }

  Future<int> dismissAllLowStockAlerts(String branchId) async {
    final result =
        await _db.rpc('dismiss_all_low_stock_alerts', params: {'p_branch': branchId});
    return result is num ? result.toInt() : 0;
  }

  Future<void> adjustStock({
    required String batchId,
    required int change,
    required String type,
    required String reason,
    String? idempotencyKey,
  }) =>
      _coordinator.run<void>(
        operation: Mutation.adjustStock,
        key: idempotencyKey ?? WriteIdempotency.newKey(Mutation.adjustStock),
        action: () async {
          await _db.rpc('adjust_stock', params: {
            'p_batch': batchId,
            'p_change': change,
            'p_type': type,
            'p_reason': reason,
          });
        },
      );

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
