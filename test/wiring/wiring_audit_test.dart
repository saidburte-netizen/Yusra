import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

void main() {
  final root = _repoRoot().path;
  final audit = auditWiring(root);

  test('wiring audit has no unjustified gaps', () {
    expect(
      audit.unjustifiedGaps.map((g) => g.key).toList(),
      isEmpty,
      reason: 'Every gap must be fixed or carry evidence-backed justification.',
    );
    expect(audit.hasUnjustifiedGaps, isFalse);
  });

  test('wiring audit records the expected deferred code fixes', () {
    final actual = audit.deferredCodeFixGaps.map((g) => g.key).toList();
    expect(
      actual,
      unorderedEquals(const <String>[
        'backward/route_reachable|/inventory/categories',
        'backward/route_reachable|/inventory/batches',
        'backward/route_reachable|/inventory/adjustments',
        'backward/route_reachable|/inventory/movements',
        'backward/route_reachable|/inventory/stocktake',
        'backward/schema_check_coverage|write_activity_log',
        'backward/schema_check_coverage|rls_activity_read',
        'backward/dashboard_tile_reconciliation|grossProfitToday',
      ]),
    );
  });

  test('wiring audit extracts the critical forward-wiring surfaces', () {
    final inv = audit.inventory;
    final paths = inv.routes.map((r) => r.path).toSet();

    expect(inv.libFiles, isNotEmpty);
    expect(
        paths,
        containsAll(<String>[
          '/dashboard',
          '/pos',
          '/sales',
          '/inventory',
          '/reports',
        ]));
    expect(inv.handlers, isNotEmpty);
    expect(inv.providers, isNotEmpty);
    expect(inv.repoMethods, isNotEmpty);

    expect(inv.dbCalls.any((c) => c.kind == 'rpc' && c.name == 'create_sale'),
        isTrue,
        reason: 'POS checkout must be traced to create_sale.');
    expect(inv.dbCalls.any((c) => c.kind == 'table' && c.name == 'sale_items'),
        isTrue);
    expect(inv.grantedFunctions, contains('create_sale'));
    expect(inv.ciJobs.any((job) => job.endsWith('→ build')), isTrue,
        reason: 'The matrix must cite the build job that runs these tests.');
    expect(inv.ciJobs.any((job) => job.endsWith('→ db-test')), isTrue);
    expect(inv.ciJobs.any((job) => job.endsWith('→ smoke-test')), isTrue);
  });

  test('migration contract functions keep their arity and schema coverage', () {
    final inv = audit.inventory;
    final objectKeys = inv.dbObjects.map((o) => o.key).toSet();
    expect(
        objectKeys,
        containsAll(<String>[
          'add_stock_batch/7',
          'add_stock_batch/8',
          'add_opening_stock/2',
          'create_draft_purchase_orders/2',
          'v_reorder_suggestions',
        ]));

    for (final name in const <String>[
      'add_stock_batch',
      'add_opening_stock',
      'create_draft_purchase_orders',
      'v_reorder_suggestions',
    ]) {
      expect(inv.schemaCheckText, contains(name),
          reason: '$name must be asserted by schema_check.sql.');
    }
  });

  test('generated matrix contains every audit section and deferred fix', () {
    final matrixFile = File('$root/docs/WIRING_MATRIX.md');
    expect(matrixFile.existsSync(), isTrue);
    final matrix = matrixFile.readAsStringSync();

    expect(matrix, startsWith('# Wiring matrix'));
    for (final snippet in const <String>[
      '## 1. Summary',
      '## 2. Forward checks',
      '## 3. Route reachability (backward)',
      '## 4. Database object coverage (backward)',
      '## 5. Dashboard tile reconciliation',
      '## 6. Repository methods → DB objects',
      '## 7. Gaps and justifications',
      'DEFERRED CODE FIX',
    ]) {
      expect(matrix, contains(snippet));
    }

    for (final gap in audit.deferredCodeFixGaps) {
      expect(matrix, contains(gap.check),
          reason: '${gap.key} must appear in the generated matrix.');
      expect(matrix, contains(gap.subject));
    }
  });
}
