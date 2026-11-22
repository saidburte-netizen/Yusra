// UI/DB role consistency checks over the generated role-matrix artifacts.
//
// The artifacts are produced by `dart run tool/gen_role_matrix.dart`; this test
// never hand-maintains the expected roles or routes. Tests 1 and 2 intentionally
// fail while known UI/DB mismatches remain in the code.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_role_matrix.dart' as gen;

const String _jsonFile = 'supabase/role_permissions.json';
const String _docFile = 'docs/ROLE_MATRIX.md';

Map<String, dynamic> loadPayload() =>
    jsonDecode(File(_jsonFile).readAsStringSync()) as Map<String, dynamic>;

String loadDoc() => File(_docFile).readAsStringSync();

List<String> asStrings(Object? value) =>
    (value as List<dynamic>?)?.cast<String>() ?? <String>[];

bool dbAllows(Map<String, dynamic> operation, String role) =>
    operation['all_authenticated'] == true ||
    asStrings(operation['roles']).contains(role) ||
    asStrings(operation['own_roles']).contains(role);

List<String> uiRejectedByDb(Map<String, dynamic> payload) {
  final operations = payload['operations'] as Map<String, dynamic>;
  final actions = payload['ui_actions'] as Map<String, dynamic>;
  final found = <String>[];
  for (final entry in actions.entries) {
    final action = entry.value as Map<String, dynamic>;
    final operation =
        operations[action['db_operation']] as Map<String, dynamic>;
    if (operation['internal'] == true) continue;
    for (final role in asStrings(action['ui_roles'])) {
      if (!dbAllows(operation, role)) {
        found.add(
            '${entry.key} / $role: UI ${action['evidence']} is rejected by '
            '${action['db_operation']} (${operation['evidence']})');
      }
    }
  }
  return found;
}

List<String> dbHiddenFromUi(Map<String, dynamic> payload) {
  final operations = payload['operations'] as Map<String, dynamic>;
  final actions = payload['ui_actions'] as Map<String, dynamic>;
  final roles = asStrings(payload['roles']);
  final found = <String>[];
  for (final entry in actions.entries) {
    final action = entry.value as Map<String, dynamic>;
    final operation =
        operations[action['db_operation']] as Map<String, dynamic>;
    if (operation['internal'] == true) continue;
    final uiRoles = asStrings(action['ui_roles']).toSet();
    for (final role in roles) {
      if (!uiRoles.contains(role) && dbAllows(operation, role)) {
        found.add('${entry.key} / $role: ${action['db_operation']} '
            '(${operation['evidence']}) allows the role but UI '
            '${action['evidence']} hides it');
      }
    }
  }
  final unmapped = payload['unmapped_objects'] as Map<String, dynamic>;
  for (final entry in unmapped.entries) {
    final object = entry.value as Map<String, dynamic>;
    if (object['internal'] != true) {
      found.add('${entry.key}: ${object['evidence']} has no UI action and is '
          'not tagged internal');
    }
  }
  return found;
}

int routeDeclarationCount() {
  final files = <File>[File('lib/core/router.dart')];
  final features = Directory('lib/features');
  if (features.existsSync()) {
    for (final entity in features.listSync(recursive: true)) {
      if (entity.path.endsWith('_routes.dart')) files.add(File(entity.path));
    }
  }
  return files.fold<int>(
    0,
    (count, file) =>
        count +
        RegExp(r'GoRoute\s*\(').allMatches(file.readAsStringSync()).length,
  );
}

void main() {
  test('no UI action is rejected by the database for any role', () {
    final blocked = uiRejectedByDb(loadPayload());
    expect(
      blocked,
      isEmpty,
      reason: 'UI exposes actions the database rejects:\n${blocked.join('\n')}',
    );
  });

  test('database capabilities hidden from UI are documented, not silent', () {
    final hidden = dbHiddenFromUi(loadPayload());
    final doc = loadDoc();
    final undocumented = hidden.where((gap) {
      final id = gap.split(':').first.trim();
      return !doc.contains(id);
    }).toList();
    expect(
      undocumented,
      isEmpty,
      reason: 'Undocumented DB/UI gaps (add to docs/ROLE_MATRIX.md or tag '
          'internal):\n${undocumented.join('\n')}',
    );
  });

  test('generated artifacts match the code sources', () {
    final stale = gen.staleArtifacts();
    expect(
      stale,
      isEmpty,
      reason: 'Run dart run tool/gen_role_matrix.dart for: ${stale.join(', ')}',
    );
  });

  test('all six roles and every route are covered', () {
    final payload = loadPayload();
    final doc = loadDoc();
    expect(
      asStrings(payload['roles']),
      <String>[
        'super_admin',
        'admin',
        'pharmacist',
        'cashier',
        'store_keeper',
        'accountant',
      ],
    );

    final routeSection = doc.split('## 3. Screen actions by role').first;
    final routeRows =
        RegExp(r'^\| `/', multiLine: true).allMatches(routeSection).length;
    expect(
      routeRows,
      routeDeclarationCount(),
      reason: 'The route table must contain one row per GoRoute declaration',
    );
    expect(
      routeSection,
      contains('| Bottom nav | Drawer | Dashboard quick actions |'),
      reason: 'Navigation placement must be reported for every route',
    );
    final actions = payload['ui_actions'] as Map<String, dynamic>;
    for (final entry in actions.values) {
      final action = entry as Map<String, dynamic>;
      expect(
        routeSection.contains('`${action['route']}`'),
        isTrue,
        reason: 'Action ${action['label']} points at an undocumented route',
      );
    }
  });

  test(
      'opening stock, needs ordering and the add-stock source selector are covered',
      () {
    final payload = loadPayload();
    final actions = payload['ui_actions'] as Map<String, dynamic>;
    for (final id in <String>[
      'stock.add',
      'stock.source',
      'stock.opening.entry',
      'stock.opening.save',
      'stock.needsOrdering.entry',
      'stock.needsOrdering.create',
      'stock.needsOrdering.exportCsv',
      'stock.needsOrdering.exportPdf',
    ]) {
      expect(actions.containsKey(id), isTrue, reason: 'Missing UI action $id');
    }
    final source = actions['stock.source']! as Map<String, dynamic>;
    expect(source['label'], contains('opening / purchase / other'));

    final operations = payload['operations'] as Map<String, dynamic>;
    for (final id in <String>[
      'rpc.add_stock_batch',
      'rpc.add_opening_stock',
      'rpc.create_draft_purchase_orders',
    ]) {
      expect(operations.containsKey(id), isTrue, reason: 'Missing DB rule $id');
    }
    final doc = loadDoc();
    expect(doc, contains('opening|purchase|other'));
    expect(doc, contains('Opening stock'));
    expect(doc, contains('Needs ordering'));
  });
}
