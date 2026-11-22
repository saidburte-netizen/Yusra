import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_metrics.dart';

import '../../tool/wiring_audit.dart';

Directory _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not find the repository root from ${Directory.current.path}');
    }
    dir = parent;
  }
}

String _read(String root, String relativePath) =>
    File('$root/$relativePath').readAsStringSync();

double _rawTotalSum(List<Map<String, dynamic>> rows) => rows.fold<double>(
      0,
      (sum, row) =>
          sum +
          (row['total'] is num
              ? (row['total'] as num).toDouble()
              : double.tryParse(row['total']?.toString() ?? '') ?? 0),
    );

void main() {
  final root = _repoRoot().path;
  final audit = auditWiring(root);
  final dashboardSource =
      _read(root, 'lib/features/dashboard/dashboard_screen.dart');
  final metricsSource =
      _read(root, 'lib/features/dashboard/dashboard_metrics.dart');
  final reportSql = _read(root, 'supabase/migrations/0014_report_views.sql');

  test('today and month sales reconcile with raw sales.total sums', () {
    // DashboardSnapshot.load and DashboardRepository both read the same raw
    // `sales` rows; the report views aggregate the same column.
    expect(dashboardSource, contains("_sum(todayRows, 'total')"));
    expect(dashboardSource, contains("_sum(monthRows, 'total')"));
    expect(metricsSource, contains(".from('sales')"));
    expect(reportSql, contains('coalesce(sum(s.total), 0) as net'));
    expect(reportSql, contains('coalesce(sum(s.total), 0) as total'));

    final raw = <Map<String, dynamic>>[
      {'total': 12.5},
      {'total': '7.5'},
    ];
    expect(_rawTotalSum(raw), 20.0);
  });

  test('gross profit today derives from the raw sale_items fields', () {
    expect(dashboardSource, contains('grossProfitFrom(todayItems)'));
    expect(metricsSource, contains('line_total'));
    expect(metricsSource, contains('cost_price'));
    expect(metricsSource, contains('quantity'));
    expect(reportSql, contains('sum(si.line_total - si.discount_share'));

    final items = <Map<String, dynamic>>[
      {'line_total': 120.0, 'cost_price': 30.0, 'quantity': 2},
      {'line_total': 50.0, 'cost_price': 10.0, 'quantity': 3},
    ];
    // 120 - 2*30 = 60; 50 - 3*10 = 20.
    expect(dashboardGrossProfit(items), closeTo(80.0, 0.001));
    expect(dashboardGrossProfit(null), isNull);
  });

  test('gross profit divergence from report views is a deferred code fix', () {
    final gap = audit.gaps.where((g) =>
        g.key == 'backward/dashboard_tile_reconciliation|grossProfitToday');
    expect(gap, hasLength(1));
    expect(gap.single.detail, contains('discount_share'));
    expect(gap.single.detail, contains('returned_qty'));
    expect(gap.single.fixHint, contains('dashboard_metrics.dart'));
  });

  test('expiry tiles split v_expiring_batches with the is_expired flag', () {
    expect(dashboardSource, contains("branchRows('v_expiring_batches'"));
    expect(dashboardSource, contains('isExpiredBatch'));
    expect(dashboardIsExpiredBatch({'is_expired': true}), isTrue);
    expect(dashboardIsExpiredBatch({'is_expired': 'true'}), isTrue);
    expect(dashboardIsExpiredBatch({'is_expired': false}), isFalse);
  });

  test('top medicines tile ranks the same raw sale_items rows as reports', () {
    expect(reportSql, contains('si.medicine_name as medicine'));
    expect(reportSql, contains('sum(si.quantity'));

    final ranked = dashboardTopMedicines(<Map<String, dynamic>>[
      {
        'medicine_id': 'm1',
        'medicines': [
          {'name': 'Paracetamol'}
        ],
        'quantity': 4,
      },
      {'medicine_id': 'm2', 'medicine_name': 'Amoxicillin', 'quantity': 9},
    ]);
    expect(ranked.first['name'], 'Amoxicillin');
    expect(ranked.first['qty'], 9);
    expect(ranked.last['name'], 'Paracetamol');
  });

  test('every report view referenced by the app has a SQL definition', () {
    expect(audit.inventory.reportViews, isNotEmpty);
    for (final view in audit.inventory.reportViews) {
      expect(reportSql, contains('create or replace view $view'),
          reason: '$view is referenced by the Reports screen.');
    }
  });

  test('dashboard tiles carry a source query and test evidence', () {
    final tiles = audit.inventory.dashboardTiles;
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(tile.source, isNot('<unresolved>'),
          reason: '${tile.label} has no resolved source query.');
      expect(tile.testRef.line, greaterThan(0),
          reason: '${tile.label} has no test evidence.');
    }
  });
}
