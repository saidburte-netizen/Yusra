// Generates docs/ROLE_MATRIX.md and supabase/role_permissions.json from code.
//
// Run from the repository root:
//   dart run tool/gen_role_matrix.dart
//   dart run tool/gen_role_matrix.dart --check   # fails if artifacts are stale
//
// This tool deliberately has no Flutter/Supabase dependencies: it reads the
// router, navigation, permission map, screen sources, SQL migrations and Edge
// Functions as text, then emits both artifacts. Nothing in the matrix is
// hand-maintained; fix the source of truth and re-run the generator.

import 'dart:convert';
import 'dart:io';

const String _permissionsFile = 'lib/core/permissions.dart';
const String _routerFile = 'lib/core/router.dart';
const String _menuFile = 'lib/core/nav/menu_items.dart';
const String _shellFile = 'lib/core/nav/app_shell.dart';
const String _dashboardFile = 'lib/features/dashboard/dashboard_screen.dart';
const String _docFile = 'docs/ROLE_MATRIX.md';
const String _jsonFile = 'supabase/role_permissions.json';

/// Valid SQLSTATE/app_role literals; used when reading role checks out of SQL.
const List<String> _knownRoles = <String>[
  'super_admin',
  'admin',
  'pharmacist',
  'cashier',
  'store_keeper',
  'accountant',
];

/// Operations that are database plumbing (triggers, document numbering, auth
/// helpers). They have no user-facing button, so the role-matrix test ignores
/// them; they are still listed in the JSON with `internal: true`.
const Set<String> _internalPrefixes = <String>{
  'approve_',
  'audit_',
  'cancel_',
  'guard_',
  'handle_',
  'has_role',
  'my_',
  'next_',
  'protect_',
  'recalc_',
  'reject_',
  'set_updated_at',
  'trg_',
  'write_',
  'can_access_branch',
};

class SourceRef {
  const SourceRef(this.file, this.line, [this.detail = '']);

  final String file;
  final int line;
  final String detail;

  @override
  String toString() => '$file:$line${detail.isEmpty ? '' : ' ($detail)'}';
}

class RouteInfo {
  RouteInfo({
    required this.path,
    required this.screen,
    required this.file,
    required this.line,
    required this.module,
  });

  final String path;
  final String screen;
  final String file;
  final int line;
  final String? module;
}

class MenuInfo {
  MenuInfo({
    required this.label,
    required this.path,
    required this.module,
    required this.line,
  });

  final String label;
  final String path;
  final String module;
  final int line;
}

class ActionSpec {
  const ActionSpec({
    required this.id,
    required this.route,
    required this.label,
    required this.kind,
    required this.gate,
    required this.file,
    required this.snippet,
    required this.dbKey,
    this.note = '',
  });

  final String id;
  final String route;
  final String label;
  final String kind;
  final String gate;
  final String file;
  final String snippet;
  final String dbKey;
  final String note;
}

class DbRule {
  DbRule({
    required this.id,
    required this.roles,
    required this.ref,
    this.ownRoles = const <String>{},
    this.internal = false,
    this.note = '',
    this.allAuthenticated = false,
  });

  final String id;
  final Set<String> roles;
  final Set<String> ownRoles;
  final SourceRef ref;
  final bool internal;
  final String note;
  final bool allAuthenticated;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'roles': roles.toList()..sort(),
        if (ownRoles.isNotEmpty) 'own_roles': ownRoles.toList()..sort(),
        'evidence': ref.toString(),
        'all_authenticated': allAuthenticated,
        'internal': internal,
        'note': note,
      };
}

class Analysis {
  Analysis(this.root);

  final String root;

  late final List<String> roles;
  late final Map<String, String> roleLabels;
  late final Map<String, String> homeFor;
  late final Map<String, Map<String, String>> permissions;
  late final List<MenuInfo> menu;
  late final List<String> bottomPreferred;
  late final List<RouteInfo> routes;
  late final Map<String, DbRule> dbRules;
  late final List<DbRule> unmappedDbRules;
  late final List<ActionSpec> actions;
  late final Map<String, SourceRef> sqlObjectRefs;

  final Map<String, String> _sources = <String, String>{};
  final Map<String, Map<String, dynamic>> _policies =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _functions =
      <String, Map<String, dynamic>>{};

  String read(String relative) => _sources.putIfAbsent(
      relative, () => File('$root/$relative').readAsStringSync());

  static int lineAt(String source, int offset) =>
      source.substring(0, offset).split('\n').length;

  /// Returns the content between an opening `{`, `[` or `(` at [open].
  static String balanced(String source, int open) {
    final opener = source[open];
    final close = opener == '{'
        ? '}'
        : opener == '['
            ? ']'
            : ')';
    var depth = 0;
    var quote = '';
    for (var i = open; i < source.length; i++) {
      final ch = source[i];
      if (quote.isNotEmpty) {
        if (ch == r'\') {
          i++;
        } else if (ch == quote) {
          quote = '';
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
      } else if (ch == opener) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) return source.substring(open + 1, i);
      }
    }
    throw FormatException('Unbalanced $opener at $open');
  }

  static List<String> quotedRoles(String text) {
    final found = <String>{};
    for (final match in RegExp(r"'([a-z_]+)'").allMatches(text)) {
      if (_knownRoles.contains(match.group(1))) found.add(match.group(1)!);
    }
    return found.toList();
  }

  static Set<String> hasRoleRoles(String text) {
    final found = <String>{};
    for (final match in RegExp(r'has_role\s*\(([^)]*)\)').allMatches(text)) {
      found.addAll(quotedRoles(match.group(1)!));
    }
    return found;
  }

  Analysis analyze() {
    _readPermissions();
    _readNavigation();
    _readRoutes();
    _readSql();
    _buildDbRules();
    actions = _actionSpecs();
    return this;
  }

  void _readPermissions() {
    final src = read(_permissionsFile);
    final enumStart = src.indexOf('enum AppRole {');
    final enumBody = balanced(src, src.indexOf('{', enumStart));
    roles = enumBody
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final dbStart = src.indexOf('String get dbName');
    final dbEnd = src.indexOf('String get label', dbStart);
    final dbBlock = src.substring(dbStart, dbEnd);
    roleLabels = <String, String>{};
    for (final match
        in RegExp(r"AppRole\.(\w+)\s*=>\s*'([^']+)'").allMatches(dbBlock)) {
      roleLabels[match.group(1)!] = match.group(2)!;
    }
    for (final role in roles) {
      if (!roleLabels.containsKey(role)) {
        throw StateError('Missing dbName for $role in $_permissionsFile');
      }
    }

    final matrixStart =
        src.indexOf('const Map<String, Map<AppRole, Perm>> permissionMatrix');
    final matrixBody =
        balanced(src, src.indexOf('{', matrixStart + 'const Map'.length + 40));
    permissions = <String, Map<String, String>>{};
    for (final moduleMatch
        in RegExp(r'Modules\.(\w+):\s*\{').allMatches(matrixBody)) {
      final body =
          balanced(matrixBody, matrixBody.indexOf('{', moduleMatch.start));
      final module = <String, String>{};
      for (final match
          in RegExp(r'AppRole\.(\w+):\s*_(e|v|o|n)').allMatches(body)) {
        module[match.group(1)!] = match.group(2)!.toUpperCase();
      }
      permissions[moduleMatch.group(1)!] = module;
    }

    final menuSrc = read(_menuFile);
    final homeStart = menuSrc.indexOf('String homeFor(');
    if (homeStart < 0) throw StateError('homeFor() not found in $_menuFile');
    final homeBody = balanced(menuSrc, menuSrc.indexOf('{', homeStart));
    homeFor = <String, String>{};
    for (final match
        in RegExp(r"([^,]+?)=>\s*'([^']+)'").allMatches(homeBody)) {
      final path = match.group(2)!;
      for (final roleMatch
          in RegExp(r'AppRole\.(\w+)').allMatches(match.group(1)!)) {
        homeFor[roleMatch.group(1)!] = path;
      }
    }
    for (final role in roles) {
      if (!homeFor.containsKey(role)) {
        throw StateError('Missing homeFor for $role in $_menuFile');
      }
    }
  }

  void _readNavigation() {
    final src = read(_menuFile);
    final menuStart = src.indexOf('const List<MenuItem> allMenuItems');
    final menuBody = balanced(src, src.indexOf('[', menuStart));
    menu = <MenuInfo>[];
    for (final match in RegExp(r'MenuItem\s*\(').allMatches(menuBody)) {
      final body = balanced(menuBody, menuBody.indexOf('(', match.start));
      final path = RegExp(r"path:\s*'([^']+)'").firstMatch(body)!.group(1)!;
      final module =
          RegExp(r'module:\s*Modules\.(\w+)').firstMatch(body)!.group(1)!;
      final labelMatch = RegExp(r'label:\s*S\.(\w+)').firstMatch(body);
      final label = labelMatch?.group(1) ?? path;
      menu.add(MenuInfo(
        label: label,
        path: path,
        module: module,
        line: lineAt(src, menuStart + match.start),
      ));
    }
    final prefStart = src.indexOf('const List<String> _preferredBottomNav');
    if (prefStart == -1) {
      bottomPreferred = menu.map((m) => m.path).toList();
    } else {
      final prefBody = balanced(src, src.indexOf('[', prefStart));
      bottomPreferred = RegExp(r"'([^']+)'")
          .allMatches(prefBody)
          .map((m) => m.group(1)!)
          .toList();
    }

    // Fail loudly when the navigation code changes shape instead of silently
    // emitting a matrix that no longer matches it.
    if (!read(_shellFile).contains('bottomNavItems(role)')) {
      throw StateError('AppShell no longer calls bottomNavItems(role)');
    }
    if (!read(_dashboardFile).contains(
        "menuFor(role)\n        .where((item) => item.path != '/dashboard')\n        .take(4)")) {
      throw StateError('Dashboard quick actions no longer use menuFor(role)');
    }
  }

  void _readRoutes() {
    routes = <RouteInfo>[];
    final files = <String>[_routerFile];
    final features = Directory('$root/lib/features');
    for (final entity in features.listSync(recursive: true)) {
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('_routes.dart')) {
        files.add(path.substring(root.length + 1));
      }
    }
    files.sort();
    for (final file in files) {
      final src = read(file);
      for (final match in RegExp(r'GoRoute\s*\(').allMatches(src)) {
        final open = src.indexOf('(', match.start);
        final body = balanced(src, open);
        final pathMatch = RegExp(r"path:\s*'([^']+)'").firstMatch(body);
        if (pathMatch == null) continue;
        final builderMatch = RegExp(
                r'builder:\s*\(context,\s*state\)\s*=>\s*(?:const\s+)?([A-Za-z_]\w*)\s*\(')
            .firstMatch(body);
        final path = pathMatch.group(1)!;
        routes.add(RouteInfo(
          path: path,
          screen: builderMatch?.group(1) ?? '(shell)',
          file: file,
          line: lineAt(src, open + pathMatch.start),
          module: _moduleFor(path, src),
        ));
      }
    }
    if (routes.isEmpty) throw StateError('No GoRoute declarations found');
  }

  String? _moduleFor(String path, String routerSource) {
    if (path == '/sales/returns' || path.startsWith('/sales/returns/')) {
      return 'saleReturns';
    }
    final stockStart = routerSource.indexOf('const stockPaths = [');
    if (stockStart != -1) {
      final stockBody =
          balanced(routerSource, routerSource.indexOf('[', stockStart));
      for (final match in RegExp(r"'([^']+)'").allMatches(stockBody)) {
        final stockPath = match.group(1)!;
        if (path == stockPath || path.startsWith('$stockPath/')) return 'stock';
      }
    }
    final matches = menu
        .where((item) => path == item.path || path.startsWith('${item.path}/'))
        .toList();
    if (matches.isEmpty) return null;
    // Longest prefix wins (e.g. /admin/users before any generic /admin rule).
    matches.sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.first.module;
  }

  void _readSql() {
    final dir = Directory('$root/supabase/migrations');
    final files = dir
        .listSync()
        .where((e) => e.path.endsWith('.sql'))
        .map((e) => e.path.replaceAll('\\', '/'))
        .map((p) => p.substring(root.length + 1))
        .toList()
      ..sort();
    for (final file in files) {
      final src = read(file);
      for (final match in RegExp(
              r'create policy\s+(\w+)\s+on\s+([\w.]+)\s+for\s+(SELECT|ALL|INSERT|UPDATE|DELETE)\s+to\s+(\w+)',
              caseSensitive: false)
          .allMatches(src)) {
        final name = match.group(1)!;
        final semicolon = src.indexOf(';', match.end);
        final statement = semicolon == -1
            ? src.substring(match.end)
            : src.substring(match.end, semicolon);
        var detail = '';
        final usingAt = statement.indexOf('using (');
        if (usingAt != -1) {
          detail += balanced(statement, statement.indexOf('(', usingAt));
        }
        final checkAt = statement.indexOf('with check (');
        if (checkAt != -1) {
          detail += ' ${balanced(statement, statement.indexOf('(', checkAt))}';
        }
        final roles = hasRoleRoles(detail);
        final ownRoles = <String>[];
        if (detail.contains('cashier_id = auth.uid()')) {
          ownRoles.add('cashier');
        }
        if (RegExp(r'(actor_id|processed_by|p_user|owner)\s*=\s*auth\.uid\(\)')
            .hasMatch(detail)) {
          ownRoles.addAll(_knownRoles);
        }
        if (detail.contains('storage.foldername(name))[1] = auth.uid()') ||
            RegExp(r'\bid\s*=\s*auth\.uid\(\)').hasMatch(detail) &&
                roles.isNotEmpty) {
          ownRoles.addAll(_knownRoles);
        }
        // Policies without a has_role() check are branch/row scoped but open
        // to every authenticated caller (e.g. can_access_branch or using true).
        final allAuthenticated =
            roles.isEmpty && ownRoles.isEmpty ? true : false;
        if (allAuthenticated) roles.addAll(_knownRoles);
        _policies[name] = <String, dynamic>{
          'name': name,
          'table': match.group(2)!,
          'action': match.group(3)!.toUpperCase(),
          'roles': roles.toList(),
          'ownRoles': ownRoles.toSet().toList(),
          'allAuthenticated': allAuthenticated,
          'file': file,
          'line': lineAt(src, match.start),
          'detail': detail,
        };
      }
      for (final match in RegExp(
              r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?(\w+)\s*\(',
              caseSensitive: false)
          .allMatches(src)) {
        final name = match.group(1)!;
        final dollar = src.indexOf('\$\$', match.end);
        if (dollar == -1) continue;
        final bodyStart = dollar + 2;
        final bodyEnd = src.indexOf('\$\$', bodyStart);
        if (bodyEnd == -1) continue;
        final body = src.substring(bodyStart, bodyEnd);
        final roles = <String>{};
        roles.addAll(hasRoleRoles(body));
        for (final roleMatch in RegExp(
                r"'(super_admin|admin|pharmacist|cashier|store_keeper|accountant)'")
            .allMatches(body)) {
          final context = body.substring(
            roleMatch.start < 90 ? 0 : roleMatch.start - 90,
            (roleMatch.end + 30).clamp(0, body.length),
          );
          if (context.contains('my_role') ||
              context.contains('v_caller_role') ||
              context.contains('v_role') ||
              context.contains('not in') ||
              context.contains('is distinct from') ||
              context.contains('<>') ||
              context.contains("'= '")) {
            roles.add(roleMatch.group(1)!);
          }
        }
        final ownRoles = <String>[];
        // Only genuine row-ownership predicates count as an own-scope
        // capability. Parameter guards such as `p_user = auth.uid()` or
        // duplicate-shift checks are not UI actions.
        if (body.contains('v_actor is distinct from auth.uid()') ||
            name.startsWith('get_my_') ||
            name.startsWith('update_my_') ||
            body.contains('storage.foldername(name))[1] = auth.uid()')) {
          ownRoles.addAll(_knownRoles);
        }
        final existing = _functions[name];
        if (existing == null) {
          _functions[name] = <String, dynamic>{
            'name': name,
            'roles': roles.toList(),
            'ownRoles': ownRoles.toSet().toList(),
            'file': file,
            'line': lineAt(src, match.start),
            'body': body,
          };
        } else {
          // Overloads share a name; a thin wrapper may delegate its role check
          // to another overload, so merge instead of overwriting the evidence.
          final merged = <String>{
            ...(existing['roles'] as List).cast<String>(),
            ...roles
          };
          final mergedOwn = <String>{
            ...(existing['ownRoles'] as List).cast<String>(),
            ...ownRoles,
          };
          final preferCurrent =
              (existing['roles'] as List).isEmpty && roles.isNotEmpty;
          existing['roles'] = merged.toList();
          existing['ownRoles'] = mergedOwn.toList();
          existing['body'] = '${existing['body']}\n$body';
          if (preferCurrent) {
            existing['file'] = file;
            existing['line'] = lineAt(src, match.start);
          }
        }
      }
    }
  }

  static const Map<String, String> _operationSources = <String, String>{
    'rls.branches.write': 'policy:rls_branches_write',
    'rls.users.read': 'policy:rls_profiles_read',
    'rls.settings.write': 'policy:rls_settings_write',
    'rls.categories.write': 'policy:rls_categories_write',
    'rls.medicines.write': 'policy:rls_medicines_write',
    'rls.suppliers.write': 'policy:rls_suppliers_write',
    'rls.customers.write': 'policy:rls_customers_write',
    'rls.purchaseOrders.read': 'policy:rls_po_read',
    'rls.purchaseOrders.write': 'policy:rls_po_write',
    'rls.prescriptions.write': 'policy:rls_rx_write',
    'rls.expenses.write': 'policy:rls_expenses_write',
    'rls.sales.read': 'policy:rls_sales_read',
    'rls.activity.read': 'policy:rls_activity_read',
    'storage.medicine-images.write': 'policy:rls_medicine_images_write',
    'storage.prescriptions.write': 'policy:rls_rx_storage_write',
    'storage.receipts.write': 'policy:rls_receipts_write',
    'storage.avatars.write': 'policy:rls_avatars_write',
    'storage.branding.write': 'policy:rls_branding_write',
    'rpc.add_stock_batch': 'function:add_stock_batch',
    'rpc.add_opening_stock': 'function:add_opening_stock',
    'rpc.create_draft_purchase_orders': 'function:create_draft_purchase_orders',
    'rpc.adjust_stock': 'function:adjust_stock',
    'rpc.receive_purchase_order': 'function:receive_purchase_order',
    'rpc.set_purchase_order_status': 'function:set_purchase_order_status',
    'rpc.open_shift': 'function:open_shift',
    'rpc.close_shift': 'function:close_shift',
    'rpc.create_sale': 'function:create_sale',
    'rpc.void_sale': 'function:void_sale',
    'rpc.process_sale_return': 'function:process_sale_return',
    'rpc.set_expense_status': 'function:set_expense_status',
    'rpc.set_user_access': 'function:set_user_access',
    'rpc.share_admin_access': 'function:share_admin_access',
    'rpc.publish_app_settings': 'function:publish_app_settings',
    'rpc.approve_activity_correction': 'function:approve_activity_correction',
    'rpc.request_activity_correction': 'function:request_activity_correction',
    'rpc.get_my_profile': 'function:get_my_profile',
    'rpc.update_my_profile': 'function:update_my_profile',
    'rpc.customer_stats': 'function:customer_stats',
    'rpc.shift_expected_cash': 'function:shift_expected_cash',
    'views.reports': 'grant:v_report_',
    'views.reorder': 'grant:v_reorder_suggestions',
    'edge.admin-create-user': 'edge:admin-create-user',
    'edge.admin-reset-password': 'edge:admin-reset-password',
  };

  List<String> _edgeRoles(String function) {
    // Both admin Edge Functions call isAdminRole(actor.role); ALLOWED_ROLES in
    // admin-create-user restricts the *target* role, not the caller.
    final file = 'supabase/functions/$function/index.ts';
    final src = read(file);
    if (!src.contains('isAdminRole(')) {
      throw StateError('No isAdminRole() caller check found in $file');
    }
    const shared = 'supabase/functions/_shared/validate.ts';
    final match =
        RegExp(r'ADMIN_ROLES\s*=\s*\[([^\]]*)\]').firstMatch(read(shared));
    final roles = match == null ? <String>[] : quotedRoles(match.group(1)!);
    if (roles.isEmpty) {
      throw StateError('No ADMIN_ROLES found in $shared');
    }
    return roles;
  }

  void _buildDbRules() {
    dbRules = <String, DbRule>{};
    sqlObjectRefs = <String, SourceRef>{};
    final used = <String>{};

    for (final entry in _operationSources.entries) {
      final id = entry.key;
      final source = entry.value;
      final kind = source.split(':').first;
      final name = source.substring(kind.length + 1);
      used.add(name);
      if (kind == 'policy') {
        final policy = _policies[name];
        if (policy == null) throw StateError('Policy $name not found in SQL');
        final roles = (policy['roles'] as List).cast<String>().toSet();
        final ownRoles = (policy['ownRoles'] as List).cast<String>().toSet();
        dbRules[id] = DbRule(
          id: id,
          roles: roles,
          ownRoles: ownRoles,
          allAuthenticated: policy['allAuthenticated'] as bool? ?? false,
          ref: SourceRef(policy['file'] as String, policy['line'] as int),
          note: '${policy['table']} ${policy['action']}',
        );
      } else if (kind == 'function') {
        final fn = _functions[name];
        if (fn == null) throw StateError('Function $name not found in SQL');
        var roles = (fn['roles'] as List).cast<String>().toSet();
        if (roles.isEmpty) roles = _knownRoles.toSet();
        var ownRoles = (fn['ownRoles'] as List).cast<String>().toSet();
        if (name == 'close_shift' && ownRoles.isNotEmpty) {
          // close_shift accepts "own shift" for any role that may open one.
          ownRoles = (_functions['open_shift']!['roles'] as List)
              .cast<String>()
              .toSet();
        }
        dbRules[id] = DbRule(
          id: id,
          roles: roles,
          ownRoles: ownRoles,
          ref: SourceRef(fn['file'] as String, fn['line'] as int),
          note: 'SECURITY DEFINER RPC; branch scope enforced in function body',
        );
      } else if (kind == 'grant') {
        final located = _findGrant(name);
        dbRules[id] = DbRule(
          id: id,
          roles: _knownRoles.toSet(),
          ref: located,
          note: 'SELECT granted to authenticated; views are security_invoker',
          allAuthenticated: true,
        );
      } else if (kind == 'edge') {
        final file = 'supabase/functions/$name/index.ts';
        final src = read(file);
        final line = !src.contains('ALLOWED_ROLES')
            ? 1
            : lineAt(src, src.indexOf('ALLOWED_ROLES'));
        dbRules[id] = DbRule(
          id: id,
          roles: _edgeRoles(name).toSet(),
          ref: SourceRef(file, line),
          note: 'server-side caller role check',
        );
      }
      sqlObjectRefs[id] = dbRules[id]!.ref;
    }

    unmappedDbRules = <DbRule>[];
    for (final policy in _policies.values) {
      final name = policy['name'] as String;
      if (used.contains(name)) continue;
      final internal = name.endsWith('_read') ||
          name.endsWith('_delete') ||
          name.endsWith('_update') ||
          name == 'rls_poi_write';
      unmappedDbRules.add(DbRule(
        id: 'policy:$name',
        roles: (policy['roles'] as List).cast<String>().toSet(),
        ownRoles: (policy['ownRoles'] as List).cast<String>().toSet(),
        allAuthenticated: policy['allAuthenticated'] as bool? ?? false,
        ref: SourceRef(policy['file'] as String, policy['line'] as int),
        internal: internal,
        note: internal
            ? 'Backing policy for list screens, storage lifecycle or RPC-managed rows'
            : 'No UI action mapped',
      ));
    }
    for (final fn in _functions.values) {
      final name = fn['name'] as String;
      if (used.contains(name)) continue;
      final internal = _internalPrefixes.any(name.startsWith);
      unmappedDbRules.add(DbRule(
        id: 'function:$name',
        roles: ((fn['roles'] as List).cast<String>().toSet().isEmpty
            ? _knownRoles.toSet()
            : (fn['roles'] as List).cast<String>().toSet()),
        ownRoles: (fn['ownRoles'] as List).cast<String>().toSet(),
        ref: SourceRef(fn['file'] as String, fn['line'] as int),
        internal: internal,
        note: internal
            ? 'Database plumbing / trigger helper'
            : 'No UI action mapped',
      ));
    }
    unmappedDbRules.sort((a, b) => a.id.compareTo(b.id));
  }

  SourceRef _findGrant(String needle) {
    for (final file in _sources.keys
        .where((path) => path.startsWith('supabase/migrations/'))) {
      final src = _sources[file]!;
      final at = src.indexOf(needle);
      if (at == -1) continue;
      final grantAt = src.lastIndexOf('grant select', at);
      return SourceRef(file, lineAt(src, grantAt < 0 ? at : grantAt));
    }
    throw StateError('Grant for $needle not found');
  }

  // ---------------------------------------------------------------------------
  // UI action registry. Labels and files are verified against the screen source
  // at generation time; the gate is a small expression evaluated against the
  // permission map parsed above.
  // ---------------------------------------------------------------------------
  List<ActionSpec> _actionSpecs() {
    const s = 'lib/features/inventory/screens/';
    const w = 'lib/features/inventory/widgets/';
    return <ActionSpec>[
      const ActionSpec(
          id: 'stock.add',
          route: '/inventory',
          label: 'Add stock',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${s}stock_overview_screen.dart',
          snippet: "label: const Text('Add stock'),",
          dbKey: 'rpc.add_stock_batch'),
      const ActionSpec(
          id: 'stock.source',
          route: '/inventory',
          label: 'Add stock source selector (opening / purchase / other)',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${w}stock_widgets.dart',
          snippet: "label: 'Stock source',",
          dbKey: 'rpc.add_stock_batch',
          note:
              'options opening|purchase|other validated in 0022_OPENING_SOURCE'),
      const ActionSpec(
          id: 'stock.opening.entry',
          route: '/inventory',
          label: 'Opening stock (entry button)',
          kind: 'navigate',
          gate: 'can(stock,edit)',
          file: '${s}stock_overview_screen.dart',
          snippet: "label: const Text('Opening stock'),",
          dbKey: 'rpc.add_opening_stock'),
      const ActionSpec(
          id: 'stock.opening.save',
          route: '/inventory/opening-stock',
          label: 'Opening stock — Save all',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${s}opening_stock_screen.dart',
          snippet: "label: 'Save all',",
          dbKey: 'rpc.add_opening_stock'),
      const ActionSpec(
          id: 'stock.opening.import',
          route: '/inventory/opening-stock',
          label: 'Opening stock — Import CSV',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${s}opening_stock_screen.dart',
          snippet: "label: 'Import CSV',",
          dbKey: 'rpc.add_opening_stock'),
      const ActionSpec(
          id: 'stock.needsOrdering.entry',
          route: '/inventory',
          label: 'Needs ordering (entry button)',
          kind: 'navigate',
          gate: 'can(stock,edit)&&can(purchaseOrders,edit)',
          file: '${s}stock_overview_screen.dart',
          snippet: "label: const Text('Needs ordering'),",
          dbKey: 'rpc.create_draft_purchase_orders',
          note: 'extra purchaseOrders(edit) gate is stricter than the RPC'),
      const ActionSpec(
          id: 'stock.needsOrdering.create',
          route: '/inventory/needs-ordering',
          label: 'Needs ordering — Create purchase order(s)',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${s}needs_ordering_screen.dart',
          snippet: "label: 'Create purchase order(s)',",
          dbKey: 'rpc.create_draft_purchase_orders'),
      const ActionSpec(
          id: 'stock.needsOrdering.exportCsv',
          route: '/inventory/needs-ordering',
          label: 'Needs ordering — Export / share CSV',
          kind: 'export',
          gate: 'can(stock,edit)',
          file: '${s}needs_ordering_screen.dart',
          snippet: "label: 'Export / share CSV',",
          dbKey: 'views.reorder'),
      const ActionSpec(
          id: 'stock.needsOrdering.exportPdf',
          route: '/inventory/needs-ordering',
          label: 'Needs ordering — Export / share PDF',
          kind: 'export',
          gate: 'can(stock,edit)',
          file: '${s}needs_ordering_screen.dart',
          snippet: "label: 'Export / share PDF',",
          dbKey: 'views.reorder'),
      const ActionSpec(
          id: 'medicines.create',
          route: '/inventory/medicines',
          label: 'New medicine',
          kind: 'create',
          gate: 'can(medicines,edit)',
          file: '${s}medicines_screen.dart',
          snippet: "label: 'New medicine',",
          dbKey: 'rls.medicines.write'),
      const ActionSpec(
          id: 'medicines.edit',
          route: '/inventory/medicines',
          label: 'Edit medicine',
          kind: 'edit',
          gate: 'can(medicines,edit)',
          file: '${s}medicines_screen.dart',
          snippet: "tooltip: 'Edit',",
          dbKey: 'rls.medicines.write'),
      const ActionSpec(
          id: 'medicines.deactivate',
          route: '/inventory/medicines',
          label: 'Deactivate / reactivate medicine',
          kind: 'deactivate',
          gate: 'can(medicines,edit)',
          file: '${s}medicines_screen.dart',
          snippet: "item.isActive ? 'Deactivate' : 'Reactivate',",
          dbKey: 'rls.medicines.write'),
      const ActionSpec(
          id: 'medicines.image',
          route: '/inventory/medicines',
          label: 'Upload medicine image',
          kind: 'create',
          gate: 'can(medicines,edit)',
          file: '${s}medicines_screen.dart',
          snippet: "label: 'New medicine',",
          dbKey: 'storage.medicine-images.write'),
      const ActionSpec(
          id: 'categories.create',
          route: '/inventory/categories',
          label: 'New category',
          kind: 'create',
          gate: 'can(medicines,edit)',
          file: '${s}categories_screen.dart',
          snippet: "label: 'New category',",
          dbKey: 'rls.categories.write'),
      const ActionSpec(
          id: 'categories.edit',
          route: '/inventory/categories',
          label: 'Edit category',
          kind: 'edit',
          gate: 'can(medicines,edit)',
          file: '${s}categories_screen.dart',
          snippet: "tooltip: 'Edit',",
          dbKey: 'rls.categories.write'),
      const ActionSpec(
          id: 'categories.deactivate',
          route: '/inventory/categories',
          label: 'Deactivate / reactivate category',
          kind: 'deactivate',
          gate: 'can(medicines,edit)',
          file: '${s}categories_screen.dart',
          snippet: "item.isActive ? 'Deactivate' : 'Reactivate',",
          dbKey: 'rls.categories.write'),
      const ActionSpec(
          id: 'batches.adjust',
          route: '/inventory/batches',
          label: 'Add stock / adjust batch',
          kind: 'edit',
          gate: 'can(stock,edit)',
          file: '${s}batches_screen.dart',
          snippet: "label: 'Add stock',",
          dbKey: 'rpc.adjust_stock'),
      const ActionSpec(
          id: 'adjustments.create',
          route: '/inventory/adjustments',
          label: 'New adjustment',
          kind: 'create',
          gate: 'can(stock,edit)',
          file: '${s}adjustments_screen.dart',
          snippet: "label: 'New adjustment',",
          dbKey: 'rpc.adjust_stock'),
      const ActionSpec(
          id: 'stocktake.apply',
          route: '/inventory/stocktake',
          label: 'Apply stocktake variance',
          kind: 'edit',
          gate: 'can(stock,edit)',
          file: '${s}stocktake_screen.dart',
          snippet: "label: 'Apply \$_varianceLines variance(s)',",
          dbKey: 'rpc.adjust_stock'),
      const ActionSpec(
          id: 'alerts.createPo',
          route: '/inventory/alerts',
          label: 'Create purchase order (from alert)',
          kind: 'create',
          gate: 'can(purchaseOrders,edit)',
          file: '${s}alerts_screen.dart',
          snippet: "label: 'Create purchase order',",
          dbKey: 'rls.purchaseOrders.write'),
      const ActionSpec(
          id: 'suppliers.create',
          route: '/suppliers',
          label: 'New supplier',
          kind: 'create',
          gate: 'can(suppliers,edit)',
          file: 'lib/features/suppliers/screens/suppliers_screen.dart',
          snippet: "label: 'New supplier',",
          dbKey: 'rls.suppliers.write'),
      const ActionSpec(
          id: 'suppliers.edit',
          route: '/suppliers/:id',
          label: 'Edit supplier',
          kind: 'edit',
          gate: 'can(suppliers,edit)',
          file: 'lib/features/suppliers/screens/suppliers_screen.dart',
          snippet: "tooltip: 'Edit',",
          dbKey: 'rls.suppliers.write'),
      const ActionSpec(
          id: 'suppliers.deactivate',
          route: '/suppliers/:id',
          label: 'Deactivate / reactivate supplier',
          kind: 'deactivate',
          gate: 'can(suppliers,edit)',
          file: 'lib/features/suppliers/screens/suppliers_screen.dart',
          snippet: "tooltip: supplier.isActive ? 'Deactivate' : 'Reactivate',",
          dbKey: 'rls.suppliers.write'),
      const ActionSpec(
          id: 'suppliers.newPo',
          route: '/suppliers/:id',
          label: 'New purchase order (from supplier)',
          kind: 'create',
          gate: 'can(suppliers,edit)',
          file: 'lib/features/suppliers/screens/suppliers_screen.dart',
          snippet: "label: 'New purchase order',",
          dbKey: 'rls.purchaseOrders.write'),
      const ActionSpec(
          id: 'po.create',
          route: '/purchasing/orders',
          label: 'New purchase order',
          kind: 'create',
          gate: 'can(purchaseOrders,edit)',
          file: 'lib/features/purchasing/screens/purchase_orders_screen.dart',
          snippet: "label: 'New order',",
          dbKey: 'rls.purchaseOrders.write'),
      const ActionSpec(
          id: 'po.approve',
          route: '/purchasing/orders/:id',
          label: 'Approve & send / cancel purchase order',
          kind: 'approve',
          gate: 'role(super_admin,admin)',
          file: 'lib/features/purchasing/screens/purchase_order_screen.dart',
          snippet: "label: 'Approve & send',",
          dbKey: 'rpc.set_purchase_order_status'),
      const ActionSpec(
          id: 'po.receive',
          route: '/purchasing/orders/:id',
          label: 'Receive goods',
          kind: 'edit',
          gate: 'can(purchaseOrders,edit)',
          file: 'lib/features/purchasing/screens/purchase_order_screen.dart',
          snippet: "label: 'Receive goods',",
          dbKey: 'rpc.receive_purchase_order'),
      const ActionSpec(
          id: 'po.print',
          route: '/purchasing/orders/:id',
          label: 'Print PO / GRN',
          kind: 'print',
          gate: 'can(purchaseOrders,view)',
          file: 'lib/features/purchasing/screens/purchase_order_screen.dart',
          snippet: "label: 'Print PO',",
          dbKey: 'rls.purchaseOrders.read'),
      const ActionSpec(
          id: 'pos.sale',
          route: '/pos',
          label: 'Create sale / charge cart',
          kind: 'create',
          gate: 'can(pos,edit)',
          file: 'lib/features/pos/screens/pos_screen.dart',
          snippet: 'final canSell = can(role, Modules.pos, PermAction.edit);',
          dbKey: 'rpc.create_sale'),
      const ActionSpec(
          id: 'pos.shift',
          route: '/shifts',
          label: 'Start / close shift',
          kind: 'create',
          gate: 'can(pos,edit)',
          file: 'lib/features/shifts/screens/shifts_screen.dart',
          snippet: "label: _busy ? 'Working…' : 'Start shift',",
          dbKey: 'rpc.open_shift'),
      const ActionSpec(
          id: 'pos.shiftReport',
          route: '/shifts',
          label: 'X report / Z report (print)',
          kind: 'print',
          gate: 'can(pos,edit)',
          file: 'lib/features/shifts/screens/shifts_screen.dart',
          snippet: "label: 'X report',",
          dbKey: 'rpc.shift_expected_cash'),
      const ActionSpec(
          id: 'sales.reprint',
          route: '/sales',
          label: 'Reprint receipt',
          kind: 'print',
          gate: 'can(sales,view)',
          file: 'lib/features/sales/screens/sales_screen.dart',
          snippet: "tooltip: 'Reprint',",
          dbKey: 'rls.sales.read'),
      const ActionSpec(
          id: 'sales.void',
          route: '/sales',
          label: 'Void sale',
          kind: 'deactivate',
          gate: 'can(saleReturns,edit)',
          file: 'lib/features/sales/screens/sales_screen.dart',
          snippet: "child: const Text('Void sale'),",
          dbKey: 'rpc.void_sale'),
      const ActionSpec(
          id: 'sales.return',
          route: '/sales/:id',
          label: 'Process partial return',
          kind: 'create',
          gate: 'can(saleReturns,edit)',
          file: 'lib/features/sales/screens/sale_detail_screen.dart',
          snippet:
              'final canReturn = can(role, Modules.saleReturns, PermAction.edit);',
          dbKey: 'rpc.process_sale_return'),
      const ActionSpec(
          id: 'customers.create',
          route: '/customers',
          label: 'Add customer',
          kind: 'create',
          gate: 'can(customers,edit)',
          file: 'lib/features/customers/screens/customers_screen.dart',
          snippet: "label: 'Add customer',",
          dbKey: 'rls.customers.write'),
      const ActionSpec(
          id: 'customers.deactivate',
          route: '/customers',
          label: 'Deactivate / reactivate customer',
          kind: 'deactivate',
          gate: 'can(customers,edit)',
          file: 'lib/features/customers/screens/customers_screen.dart',
          snippet:
              "? 'Deactivate'\n                                                : 'Reactivate',",
          dbKey: 'rls.customers.write'),
      const ActionSpec(
          id: 'customers.stats',
          route: '/customers/:id',
          label: 'View customer stats',
          kind: 'view',
          gate: 'can(customers,view)',
          file: 'lib/features/customers/screens/customers_screen.dart',
          snippet: "tooltip: 'View',",
          dbKey: 'rpc.customer_stats'),
      const ActionSpec(
          id: 'prescriptions.register',
          route: '/prescriptions',
          label: 'Register prescription',
          kind: 'create',
          gate: 'can(prescriptions,edit)',
          file: 'lib/features/prescriptions/screens/prescriptions_screen.dart',
          snippet: "label: _busy ? 'Working…' : 'Register',",
          dbKey: 'rls.prescriptions.write'),
      const ActionSpec(
          id: 'prescriptions.cancel',
          route: '/prescriptions',
          label: 'Cancel prescription',
          kind: 'deactivate',
          gate: 'can(prescriptions,edit)',
          file: 'lib/features/prescriptions/screens/prescriptions_screen.dart',
          snippet: "tooltip: 'Cancel',",
          dbKey: 'rls.prescriptions.write'),
      const ActionSpec(
          id: 'prescriptions.image',
          route: '/prescriptions',
          label: 'Upload prescription image',
          kind: 'create',
          gate: 'can(prescriptions,edit)',
          file: 'lib/features/prescriptions/screens/prescriptions_screen.dart',
          snippet: "tooltip: 'View image',",
          dbKey: 'storage.prescriptions.write'),
      const ActionSpec(
          id: 'expenses.create',
          route: '/expenses',
          label: 'Add expense',
          kind: 'create',
          gate: 'can(expenses,edit)',
          file: 'lib/features/expenses/expenses_screen.dart',
          snippet: 'onPressed: () => _edit(null),',
          dbKey: 'rls.expenses.write'),
      const ActionSpec(
          id: 'expenses.edit',
          route: '/expenses',
          label: 'Edit / delete expense',
          kind: 'edit',
          gate: 'can(expenses,edit)',
          file: 'lib/features/expenses/expenses_screen.dart',
          snippet: "tooltip: S.edit,",
          dbKey: 'rls.expenses.write'),
      const ActionSpec(
          id: 'expenses.approve',
          route: '/expenses',
          label: 'Approve / reject expense',
          kind: 'approve',
          gate: 'role(super_admin,admin,accountant)',
          file: 'lib/features/expenses/expenses_screen.dart',
          snippet: "tooltip: 'Approve',",
          dbKey: 'rpc.set_expense_status'),
      const ActionSpec(
          id: 'expenses.receipt',
          route: '/expenses',
          label: 'Upload expense receipt',
          kind: 'create',
          gate: 'can(expenses,edit)',
          file: 'lib/features/expenses/expenses_screen.dart',
          snippet: 'onPressed: _pickReceipt,',
          dbKey: 'storage.receipts.write'),
      const ActionSpec(
          id: 'reports.export',
          route: '/reports',
          label: 'Export report PDF / CSV',
          kind: 'export',
          gate: 'can(reports,view)',
          file: 'lib/features/reports/reports_screen.dart',
          snippet: 'label: const Text(S.exportPdf),',
          dbKey: 'views.reports'),
      const ActionSpec(
          id: 'users.create',
          route: '/admin/users',
          label: 'Create user',
          kind: 'create',
          gate: 'can(users,edit)',
          file: 'lib/features/admin/users_screen.dart',
          snippet: 'label: S.createUser,',
          dbKey: 'edge.admin-create-user'),
      const ActionSpec(
          id: 'users.edit',
          route: '/admin/users',
          label: 'Edit / reset password / deactivate user',
          kind: 'edit',
          gate: 'can(users,edit)',
          file: 'lib/features/admin/users_screen.dart',
          snippet: 'tooltip: S.resetPassword,',
          dbKey: 'rpc.set_user_access'),
      const ActionSpec(
          id: 'users.reset',
          route: '/admin/users',
          label: 'Reset user password',
          kind: 'edit',
          gate: 'can(users,edit)',
          file: 'lib/features/admin/users_screen.dart',
          snippet: 'tooltip: S.resetPassword,',
          dbKey: 'edge.admin-reset-password'),
      const ActionSpec(
          id: 'team.share',
          route: '/admin/team',
          label: 'Share admin access',
          kind: 'edit',
          gate: 'can(teamAccess,edit)',
          file: 'lib/features/admin/team_access_screen.dart',
          snippet: 'icon: const Icon(Icons.group_add_outlined),',
          dbKey: 'rpc.share_admin_access'),
      const ActionSpec(
          id: 'branches.create',
          route: '/admin/branches',
          label: 'Create / edit / deactivate branch',
          kind: 'create',
          gate: 'can(branches,edit)',
          file: 'lib/features/admin/branches_screen.dart',
          snippet: 'label: S.add,',
          dbKey: 'rls.branches.write'),
      const ActionSpec(
          id: 'settings.save',
          route: '/admin/settings',
          label: 'Save setting / upload branding',
          kind: 'edit',
          gate: 'can(settings,edit)',
          file: 'lib/features/admin/settings_screen.dart',
          snippet: 'if (canEdit)',
          dbKey: 'rls.settings.write'),
      const ActionSpec(
          id: 'settings.publish',
          route: '/admin/settings',
          label: 'Publish settings',
          kind: 'approve',
          gate: 'can(settings,edit)',
          file: 'lib/features/admin/settings_screen.dart',
          snippet: 'label: S.publishSettings,',
          dbKey: 'rpc.publish_app_settings'),
      const ActionSpec(
          id: 'audit.export',
          route: '/admin/audit',
          label: 'Export audit CSV',
          kind: 'export',
          gate: 'can(audit,view)',
          file: 'lib/features/admin/audit_screen.dart',
          snippet: "exportFileName: 'yusra-activity-log.csv',",
          dbKey: 'rls.activity.read'),
      const ActionSpec(
          id: 'audit.approveCorrection',
          route: '/admin/audit',
          label: 'Approve activity correction',
          kind: 'approve',
          gate: 'role(super_admin)',
          file: 'lib/features/admin/audit_screen.dart',
          snippet: 'tooltip: S.approveCorrection,',
          dbKey: 'rpc.approve_activity_correction'),
      const ActionSpec(
          id: 'audit.requestCorrection',
          route: '/admin/audit',
          label: 'Request activity correction',
          kind: 'edit',
          gate: 'can(audit,view)&&role(admin)',
          file: 'lib/features/admin/audit_screen.dart',
          snippet: 'tooltip: S.requestCorrection,',
          dbKey: 'rpc.request_activity_correction',
          note: 'DB also allows the activity actor on any role'),
      const ActionSpec(
          id: 'profile.avatar',
          route: '/profile',
          label: 'Upload own avatar',
          kind: 'create',
          gate: 'all',
          file: 'lib/features/auth/profile_screen.dart',
          snippet: 'avatar',
          dbKey: 'storage.avatars.write'),
      const ActionSpec(
          id: 'profile.update',
          route: '/profile',
          label: 'Edit own profile',
          kind: 'edit',
          gate: 'all',
          file: 'lib/features/auth/profile_screen.dart',
          snippet: 'update_my_profile',
          dbKey: 'rpc.update_my_profile'),
    ];
  }

  // ---------------------------------------------------------------------------
  // Gate evaluation
  // ---------------------------------------------------------------------------
  bool canView(String role, String module) {
    final perm = permissions[module]?[role] ?? 'N';
    return perm == 'E' || perm == 'V' || perm == 'O';
  }

  bool canEditRole(String role, String module) =>
      permissions[module]?[role] == 'E';

  bool uiAllows(ActionSpec action, String role) => _eval(action.gate, role);

  bool _eval(String expression, String role) {
    var expr = expression.trim();
    while (expr.startsWith('(') && _closesAt(expr, 0) == expr.length - 1) {
      expr = expr.substring(1, expr.length - 1).trim();
    }
    final or = _topLevel(expr, '||');
    if (or != null) return _eval(or.$1, role) || _eval(or.$2, role);
    final and = _topLevel(expr, '&&');
    if (and != null) return _eval(and.$1, role) && _eval(and.$2, role);
    if (expr.startsWith('can(')) {
      final args = balanced(expr, 3).split(',').map((s) => s.trim()).toList();
      final module = args[0].replaceFirst('Modules.', '');
      return args[1] == 'edit'
          ? canEditRole(role, module)
          : canView(role, module);
    }
    if (expr.startsWith('role(')) {
      return balanced(expr, 4)
          .split(',')
          .map((s) => s.trim())
          .contains(dbName(role));
    }
    if (expr == 'all') return true;
    throw FormatException('Unknown gate expression: $expression');
  }

  (String, String)? _topLevel(String expr, String op) {
    var depth = 0;
    for (var i = 0; i < expr.length - 1; i++) {
      final ch = expr[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (depth == 0 && expr.startsWith(op, i)) {
        return (expr.substring(0, i), expr.substring(i + 2));
      }
    }
    return null;
  }

  int _closesAt(String expr, int open) {
    var depth = 0;
    for (var i = open; i < expr.length; i++) {
      if (expr[i] == '(') depth++;
      if (expr[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  String dbName(String camel) => roleLabels[camel] ?? camel;

  // ---------------------------------------------------------------------------
  // Mismatch detection and rendering
  // ---------------------------------------------------------------------------
  bool _dbAllows(DbRule rule, String dbRole) =>
      rule.allAuthenticated ||
      rule.roles.contains(dbRole) ||
      rule.ownRoles.contains(dbRole);

  List<String> uiRejectedByDb() {
    final out = <String>[];
    for (final action in actions) {
      final rule = dbRules[action.dbKey]!;
      if (rule.internal) continue;
      for (final role in roles) {
        if (!uiAllows(action, role)) continue;
        if (!_dbAllows(rule, dbName(role))) {
          out.add('${action.id} / ${dbName(role)}: UI ${_evidence(action)} '
              'shows "${action.label}" but ${rule.id} ${rule.ref} allows only '
              '[${rule.roles.join(', ')}]');
        }
      }
    }
    return out;
  }

  List<String> dbHiddenFromUi() {
    final out = <String>[];
    for (final action in actions) {
      final rule = dbRules[action.dbKey]!;
      if (rule.internal) continue;
      for (final role in roles) {
        if (uiAllows(action, role)) continue;
        if (_dbAllows(rule, dbName(role))) {
          out.add('${action.id} / ${dbName(role)}: ${rule.id} ${rule.ref} '
              'allows ${dbName(role)} but UI ${_evidence(action)} hides '
              '"${action.label}"');
        }
      }
    }
    for (final rule in unmappedDbRules) {
      if (!rule.internal) {
        out.add(
            '${rule.id}: ${rule.ref} is not marked internal and has no UI action');
      }
    }
    return out;
  }

  String _evidence(ActionSpec action) {
    final src = read(action.file);
    final at = src.indexOf(action.snippet);
    if (at < 0) {
      throw StateError(
          'Stale evidence for ${action.id}: "${action.snippet}" not in ${action.file}');
    }
    return '${action.file}:${lineAt(src, at)}';
  }

  List<String> menuForRole(String role) => menu
      .where((item) => canView(role, item.module))
      .map((item) => item.path)
      .toList();

  List<String> bottomForRole(String role) {
    final permitted = menu.where((item) => canView(role, item.module)).toList();
    final selected = <String>[];
    for (final path in bottomPreferred) {
      final match = permitted.where((item) => item.path == path);
      if (match.isNotEmpty) selected.add(match.first.path);
    }
    for (final item in permitted) {
      if (selected.length >= 4) break;
      if (!selected.contains(item.path)) selected.add(item.path);
    }
    return selected.take(4).toList();
  }

  List<String> quickForRole(String role) => menu
      .where((item) => item.path != '/dashboard' && canView(role, item.module))
      .map((item) => item.path)
      .take(4)
      .toList();

  String statusFor(ActionSpec action, String role) {
    final rule = dbRules[action.dbKey]!;
    final ui = uiAllows(action, role);
    final db = _dbAllows(rule, dbName(role));
    if (ui && db) return 'ALLOWED';
    if (ui && !db) return 'BLOCKED';
    return db ? 'HIDDEN†' : 'HIDDEN';
  }

  String _roleList(Iterable<String> dbNames) {
    final set = dbNames.toSet();
    if (set.length == roles.length) return 'all 6';
    if (set.isEmpty) return '—';
    return roles.where((r) => set.contains(dbName(r))).map(dbName).join(', ');
  }

  String get markdown {
    final out = StringBuffer();
    out.writeln('# Role matrix (generated)');
    out.writeln();
    out.writeln(
        '> Generated by `dart run tool/gen_role_matrix.dart` — do not edit by '
        'hand. Sources: router, navigation, permission map, screen sources, '
        'SQL migrations and Edge Functions.');
    out.writeln();
    out.writeln(
        'Legend: **ALLOWED** = UI exposes it and the database permits it; '
        '**BLOCKED** = UI exposes it but the database rejects it; **HIDDEN** = '
        'UI never exposes it; **HIDDEN†** = UI hides it although the database '
        'permits it (candidate mismatch). `own` in a DB rule means the row must '
        'belong to the caller/their shift.');
    out.writeln();
    out.writeln('Verification: `test/role/role_matrix_test.dart` tests '
        '`no UI action is rejected by the database for any role`, '
        '`no database capability is hidden from the UI without an internal tag`, '
        '`generated artifacts match the code sources`, '
        '`all six roles and every route are covered`, and '
        '`opening stock, needs ordering and the add-stock source selector are covered`. '
        'Evidence is collected by CI job `build` (`Analyze, test, build APK and web`, '
        'which runs `flutter test --exclude-tags e2e-api`), SQL rules by CI job '
        '`db-test` (`Postgres schema and migration checks`), and live API behaviour '
        'by CI job `e2e-api` (`End-to-end API tests (PostgreSQL 16 + PostgREST)`).');
    out.writeln();

    out.writeln('## 1. Roles');
    out.writeln();
    out.writeln('| DB role | Label | Home route | Code |');
    out.writeln('| --- | --- | --- | --- |');
    for (final role in roles) {
      final camel = role;
      final label = {
            'superAdmin': 'Super admin',
            'admin': 'Admin',
            'pharmacist': 'Pharmacist',
            'cashier': 'Cashier',
            'storeKeeper': 'Store keeper',
            'accountant': 'Accountant'
          }[camel] ??
          camel;
      out.writeln('| `${dbName(role)}` | $label | `${homeFor[camel] ?? '—'}` | '
          '$_permissionsFile:${lineAt(read(_permissionsFile), read(_permissionsFile).indexOf('AppRole.$camel =>'))} |');
    }
    out.writeln();

    out.writeln('## 2. Route navigation by role');
    out.writeln();
    out.writeln('Router gates routes through `moduleForLocation()` + '
        '`can(role, module, view)` ($_routerFile:156-225); menu visibility uses '
        '`menuFor(role)` ($_menuFile:112-114); the bottom bar uses '
        '`bottomNavItems(role)` ($_menuFile:127-139, $_shellFile:90-101) and the '
        'drawer uses the same `menuFor(role)` ($_shellFile:102-130). Wide screens '
        'show a `NavigationRail` with every permitted menu item '
        '($_shellFile:55-88). Dashboard quick actions are the first four '
        'permitted menu items other than `/dashboard` '
        '($_dashboardFile:652-655, 890-904).');
    out.writeln();
    out.writeln(
        '| Route | Screen | Module (router) | Router allows | Bottom nav | Drawer | Dashboard quick actions | Code |');
    out.writeln('| --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final route in routes) {
      final module = route.module;
      final allowed = module == null
          ? 'any authenticated'
          : _roleList(roles.where((r) => canView(r, module)).map(dbName));
      final bottom = _roleList(roles
          .where((r) => bottomForRole(r).contains(route.path))
          .map(dbName));
      final drawer = _roleList(
          roles.where((r) => menuForRole(r).contains(route.path)).map(dbName));
      final quick = _roleList(
          roles.where((r) => quickForRole(r).contains(route.path)).map(dbName));
      out.writeln(
          '| `${route.path}` | ${route.screen} | ${module ?? '—'} | $allowed | '
          '$bottom | $drawer | $quick | ${route.file}:${route.line} |');
    }
    out.writeln();
    out.writeln('Screen-level gates add a second check on some routes: '
        '`/inventory/opening-stock` and `/inventory/needs-ordering` require '
        '`Modules.stock(edit)` (${'lib/features/inventory/screens/opening_stock_screen.dart'}:413, '
        '${'lib/features/inventory/screens/needs_ordering_screen.dart'}:547); '
        '`/reports` requires `Modules.reports(view)` '
        '(lib/features/reports/reports_screen.dart:537).');

    out.writeln();
    out.writeln('## 3. Screen actions by role');
    out.writeln();
    out.writeln(
        '| Route | Action | Kind | UI gate (evidence) | DB rule (evidence) | '
        '${roles.map(dbName).join(' | ')} | Note |');
    out.writeln(
        '| --- | --- | --- | --- | --- | ${roles.map((_) => '---').join(' | ')} | --- |');
    for (final action in actions) {
      final rule = dbRules[action.dbKey]!;
      final roleCells = roles.map((r) => statusFor(action, r)).join(' | ');
      out.writeln('| `${action.route}` | ${action.label} | ${action.kind} | '
          '`${action.gate}` — ${_evidence(action)} | `${action.dbKey}` — ${rule.ref} | '
          '$roleCells | ${action.note} |');
    }
    out.writeln();

    out.writeln('## 4. Database rules (machine-readable copy: `$_jsonFile`)');
    out.writeln();
    out.writeln('| Operation | Allowed roles | Own-scope | Evidence | Note |');
    out.writeln('| --- | --- | --- | --- | --- |');
    for (final rule in dbRules.values) {
      out.writeln('| `${rule.id}` | ${rule.roles.join(', ')} | '
          '${rule.ownRoles.isEmpty ? '—' : rule.ownRoles.join(', ')} | ${rule.ref} | ${rule.note} |');
    }
    out.writeln();
    out.writeln(
        'Unmapped database objects (must be `internal` to be ignored by the test):');
    out.writeln();
    out.writeln('| Object | Roles | Internal | Evidence |');
    out.writeln('| --- | --- | --- | --- |');
    for (final rule in unmappedDbRules) {
      out.writeln('| `${rule.id}` | ${rule.roles.join(', ')} | '
          '${rule.internal ? 'yes' : 'NO'} | ${rule.ref} |');
    }
    out.writeln();

    final blocked = uiRejectedByDb();
    final hidden = dbHiddenFromUi();
    out.writeln('## 5. Current mismatches (test failures until fixed in code)');
    out.writeln();
    if (blocked.isEmpty && hidden.isEmpty) {
      out.writeln('None.');
    } else {
      out.writeln('### UI exposes a write the DB rejects');
      out.writeln();
      for (final item in blocked) {
        out.writeln('- $item');
      }
      if (hidden.isNotEmpty) {
        out.writeln();
        out.writeln('### DB permits an action the UI never exposes');
        out.writeln();
        for (final item in hidden) {
          out.writeln('- $item');
        }
      }
    }
    out.writeln();
    return out.toString();
  }

  String get json {
    final payload = <String, dynamic>{
      'generated_by': 'dart run tool/gen_role_matrix.dart',
      'roles': roles.map(dbName).toList(),
      'sources': <String>[
        _permissionsFile,
        _routerFile,
        _menuFile,
        _shellFile,
        _dashboardFile,
        ...routes.map((r) => r.file).toSet(),
        ..._policies.values.map((p) => p['file'] as String).toSet(),
        ..._functions.values.map((f) => f['file'] as String).toSet(),
        'supabase/functions/admin-create-user/index.ts',
        'supabase/functions/admin-reset-password/index.ts',
      ]..sort(),
      'operations': <String, dynamic>{
        for (final entry in dbRules.entries) entry.key: entry.value.toJson(),
      },
      'unmapped_objects': <String, dynamic>{
        for (final rule in unmappedDbRules) rule.id: rule.toJson(),
      },
      'ui_actions': <String, dynamic>{
        for (final action in actions)
          action.id: <String, dynamic>{
            'route': action.route,
            'label': action.label,
            'kind': action.kind,
            'gate': action.gate,
            'evidence': _evidence(action),
            'db_operation': action.dbKey,
            'ui_roles':
                roles.where((r) => uiAllows(action, r)).map(dbName).toList(),
          },
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }
}

/// Returns the generated artifacts whose contents no longer match the code.
/// Exposed so the role-matrix test can use it without spawning a subprocess.
List<String> staleArtifacts() {
  final analysis = Analysis(Directory.current.path).analyze();
  final stale = <String>[];
  final doc = File('${Directory.current.path}/$_docFile');
  final jsonFile = File('${Directory.current.path}/$_jsonFile');
  if (!doc.existsSync() || doc.readAsStringSync() != analysis.markdown) {
    stale.add(_docFile);
  }
  if (!jsonFile.existsSync() || jsonFile.readAsStringSync() != analysis.json) {
    stale.add(_jsonFile);
  }
  return stale;
}

void main(List<String> args) {
  final check = args.contains('--check');
  if (check) {
    final stale = staleArtifacts();
    for (final file in stale) {
      stderr.writeln('$file is stale; run dart run tool/gen_role_matrix.dart');
    }
    if (stale.isNotEmpty) exitCode = 1;
    return;
  }
  final analysis = Analysis(Directory.current.path).analyze();
  final doc = File('${Directory.current.path}/$_docFile');
  final jsonFile = File('${Directory.current.path}/$_jsonFile');
  doc.writeAsStringSync(analysis.markdown);
  jsonFile.writeAsStringSync(analysis.json);
  stdout.writeln(
      'Wrote $_docFile and $_jsonFile from ${analysis.routes.length} '
      'routes, ${analysis.actions.length} actions and ${analysis.dbRules.length} '
      'DB operations.');
}
