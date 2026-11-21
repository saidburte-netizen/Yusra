// Pure Dart aggregation helpers for the dashboard. Keeping them out of the
// screen widget means the numbers can be tested without Flutter, Supabase or
// the network.

num _num(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

String _medicineName(Map<String, dynamic> row) {
  final embedded = row['medicines'];
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
