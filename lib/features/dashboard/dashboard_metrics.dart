// Pure Dart aggregation helpers for the dashboard. Keeping them out of the
// screen widget means the numbers can be tested without Flutter, Supabase or
// the network.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

num _num(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

String _medicineName(Map<String, dynamic> row) {
  final embedded = row['medicine'] ?? row['medicines'];
  if (embedded is List && embedded.isNotEmpty) {
    final first = embedded.first;
    if (first is Map && first['name'] != null) {
      return first['name'].toString();
    }
  } else if (embedded is Map && embedded['name'] != null) {
    return embedded['name'].toString();
  }
  return (row['medicine_name'] as String?) ?? '—';
}

List<Map<String, dynamic>> dashboardTopMedicines(
    List<Map<String, dynamic>>? items) {
  if (items == null) return const [];
  final totals = <String, int>{};
  final names = <String, String>{};
  for (final row in items) {
    final id = row['medicine_id']?.toString();
    if (id == null || id.isEmpty) continue;
    totals[id] = (totals[id] ?? 0) + _num(row['quantity']).toInt();
    names.putIfAbsent(id, () => _medicineName(row));
  }
  final ranked = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in ranked.take(5))
      {'name': names[entry.key] ?? '—', 'qty': entry.value},
  ];
}

double? dashboardGrossProfit(List<Map<String, dynamic>>? items) {
  if (items == null) return null;
  var total = 0.0;
  for (final row in items) {
    total += _num(row['line_total']).toDouble() -
        _num(row['cost_price']).toDouble() * _num(row['quantity']).toDouble();
  }
  return total;
}

bool dashboardIsExpiredBatch(Map<String, dynamic> row) {
  final value = row['is_expired'];
  return value == true || value == 'true';
}

/// The dashboard's reads, in one place, so they can be exercised end to end.
/// The screen aggregates in Dart after these queries; no extra SQL is needed.
class DashboardRepository {
  SupabaseClient get _db => SupabaseService.client;

  List<Map<String, dynamic>> _rows(List result) => result
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList(growable: false);

  Future<List<Map<String, dynamic>>> salesBetween(
    String from,
    String to, {
    String? branchId,
    String? cashierId,
  }) async {
    var query =
        _db.from('sales').select().gte('created_at', from).lt('created_at', to);
    if (branchId != null) query = query.eq('branch_id', branchId);
    if (cashierId != null) query = query.eq('cashier_id', cashierId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> saleItemsBetween(
    String from,
    String to, {
    String? branchId,
    String? cashierId,
  }) async {
    var query = _db
        .from('sale_items')
        .select('medicine_id, medicine_name, quantity, cost_price, '
            'line_total, medicines(name), sales!inner(created_at)')
        .gte('sales.created_at', from)
        .lt('sales.created_at', to);
    if (branchId != null) query = query.eq('sales.branch_id', branchId);
    if (cashierId != null) query = query.eq('sales.cashier_id', cashierId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> lowStock(String? branchId) async {
    var query = _db.from('v_low_stock').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> expiringBatches(String? branchId) async {
    var query = _db.from('v_expiring_batches').select();
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> openShifts(String? branchId) async {
    var query = _db.from('shifts').select().eq('status', 'open');
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> pendingPrescriptions(
      String? branchId) async {
    var query = _db.from('prescriptions').select().eq('status', 'pending');
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> ordersToReceive(String? branchId) async {
    var query = _db
        .from('purchase_orders')
        .select()
        .inFilter('status', const ['ordered', 'partially_received']);
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }

  Future<List<Map<String, dynamic>>> activityLog(String? branchId) async {
    var query = _db
        .from('activity_log')
        .select('id, actor_id, actor_email, actor_role, action, entity_type, '
            'entity_id, summary, branch_id, created_at, '
            'correction_requested, correction_reason, approved_at');
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(
        await query.order('created_at', ascending: false).limit(100) as List);
  }

  Future<List<Map<String, dynamic>>> teamMembers(String? branchId) async {
    var query = _db
        .from('profiles')
        .select('id, email, full_name, role, is_active')
        .eq('is_active', true);
    if (branchId != null) query = query.eq('branch_id', branchId);
    return _rows(await query as List);
  }
}
