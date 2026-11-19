import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_providers.dart';

double _money(dynamic value) => moneyValue(value);
int _int(dynamic value) => intValue(value);

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.poNo,
    required this.branchId,
    required this.supplierId,
    this.status = 'draft',
    this.orderDate,
    this.expectedDate,
    this.notes,
    this.subtotal = 0,
    this.tax = 0,
    this.total = 0,
    this.createdAt,
  });

  final String id;
  final String poNo;
  final String branchId;
  final String supplierId;
  final String status;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final String? notes;
  final double subtotal;
  final double tax;
  final double total;
  final DateTime? createdAt;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
        id: (json['id'] as String?) ?? '',
        poNo: (json['po_no'] as String?) ?? '(draft)',
        branchId: (json['branch_id'] as String?) ?? '',
        supplierId: (json['supplier_id'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'draft',
        orderDate: json['order_date'] == null
            ? null
            : DateTime.tryParse(json['order_date'] as String),
        expectedDate: json['expected_date'] == null
            ? null
            : DateTime.tryParse(json['expected_date'] as String),
        notes: json['notes'] as String?,
        subtotal: _money(json['subtotal']),
        tax: _money(json['tax']),
        total: _money(json['total']),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );
}

class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.poId,
    required this.medicineId,
    required this.quantityOrdered,
    this.quantityReceived = 0,
    this.unitCost = 0,
    this.medicineName = '',
  });

  final String id;
  final String poId;
  final String medicineId;
  final int quantityOrdered;
  final int quantityReceived;
  final double unitCost;
  final String medicineName;

  int get remaining => quantityOrdered - quantityReceived;
  double get lineTotal => quantityOrdered * unitCost;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    final joined = json['medicines'];
    return PurchaseOrderItem(
      id: (json['id'] as String?) ?? '',
      poId: (json['po_id'] as String?) ?? '',
      medicineId: (json['medicine_id'] as String?) ?? '',
      quantityOrdered: _int(json['quantity_ordered']),
      quantityReceived: _int(json['quantity_received']),
      unitCost: _money(json['unit_cost']),
      medicineName: joined is Map
          ? (joined['name'] as String?) ?? ''
          : (json['medicine_name'] as String?) ?? '',
    );
  }
}

class PurchaseRepository {
  SupabaseClient get _db => SupabaseService.client;

  Future<List<PurchaseOrder>> orders(String? branchId) async {
    var query = _db.from('purchase_orders').select('*, suppliers(name)');
    if (branchId != null) query = query.eq('branch_id', branchId);
    final rows = await query.order('created_at', ascending: false) as List;
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return PurchaseOrder.fromJson(map);
    }).toList();
  }

  Future<PurchaseOrder> order(String id) async {
    final row = await _db.from('purchase_orders').select().eq('id', id).single();
    return PurchaseOrder.fromJson(Map<String, dynamic>.from(row));
  }

  Future<List<PurchaseOrderItem>> items(String poId) async {
    final rows = await _db
        .from('purchase_order_items')
        .select('*, medicines(name)')
        .eq('po_id', poId)
        .order('id') as List;
    return rows
        .map((row) => PurchaseOrderItem.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Creates a draft and its lines in one batch. Totals are recalculated by
  /// the database trigger `recalc_po_subtotal`.
  Future<String> createDraft({
    required String branchId,
    required String supplierId,
    required DateTime? expectedDate,
    required String? notes,
    required double tax,
    required List<PurchaseOrderItem> lines,
  }) async {
    final rows = await _db
        .from('purchase_orders')
        .insert({
          'branch_id': branchId,
          'supplier_id': supplierId,
          'status': 'draft',
          'expected_date': expectedDate == null ? null : _date(expectedDate),
          'notes': notes,
          'tax': tax,
        })
        .select('id') as List;
    final id = (rows.first as Map)['id'] as String;
    if (lines.isNotEmpty) {
      await _db.from('purchase_order_items').insert([
        for (final line in lines)
          {
            'po_id': id,
            'medicine_id': line.medicineId,
            'quantity_ordered': line.quantityOrdered,
            'unit_cost': line.unitCost,
          },
      ]);
    }
    return id;
  }

  Future<void> updateDraft({
    required String id,
    required String supplierId,
    required DateTime? expectedDate,
    required String? notes,
    required double tax,
  }) =>
      _db.from('purchase_orders').update({
        'supplier_id': supplierId,
        'expected_date': expectedDate == null ? null : _date(expectedDate),
        'notes': notes,
        'tax': tax,
      }).eq('id', id);

  Future<void> saveLines(String poId, List<PurchaseOrderItem> lines) async {
    await _db.from('purchase_order_items').delete().eq('po_id', poId);
    if (lines.isEmpty) return;
    await _db.from('purchase_order_items').insert([
      for (final line in lines)
        {
          'po_id': poId,
          'medicine_id': line.medicineId,
          'quantity_ordered': line.quantityOrdered,
          'unit_cost': line.unitCost,
        },
    ]);
  }

  /// Only admins may approve or cancel; the database guard enforces this too.
  Future<void> setStatus(String id, String status) =>
      _db.from('purchase_orders').update({'status': status}).eq('id', id);

  Future<void> receive(String poId, List<Map<String, dynamic>> items) =>
      _db.rpc('receive_purchase_order', params: {
        'p_po': poId,
        'p_items': items,
      });

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

final purchaseRepositoryProvider =
    Provider<PurchaseRepository>((ref) => PurchaseRepository());

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  if (!SupabaseService.isReady) return const <PurchaseOrder>[];
  return ref
      .read(purchaseRepositoryProvider)
      .orders(ref.watch(branchScopeProvider));
});

final purchaseOrderProvider =
    FutureProvider.family<PurchaseOrder, String>((ref, id) async {
  if (!SupabaseService.isReady) {
    return PurchaseOrder(
      id: id,
      poNo: '',
      branchId: '',
      supplierId: '',
    );
  }
  return ref.read(purchaseRepositoryProvider).order(id);
});

final purchaseItemsProvider =
    FutureProvider.family<List<PurchaseOrderItem>, String>((ref, poId) async {
  if (!SupabaseService.isReady) return const <PurchaseOrderItem>[];
  return ref.read(purchaseRepositoryProvider).items(poId);
});
