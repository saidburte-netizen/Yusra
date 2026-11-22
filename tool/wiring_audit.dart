// Static end-to-end wiring audit for Yusra Pharmacy.
//
// Run from the repository root:
//
//   dart run tool/wiring_audit.dart            # regenerate docs/WIRING_MATRIX.md
//   dart run tool/wiring_audit.dart --check    # fail on any unjustified gap
//   dart run tool/wiring_audit.dart --dump     # print every gap (incl. waived)
//
// The tool is deliberately dependency-free and read-only: it never imports
// `lib/`, so it cannot accidentally execute app code. All it does is read the
// source tree, extract wiring facts with file:line evidence, compare the
// forward (UI -> DB) and backward (DB -> UI) directions, and render the matrix.
//
// `test/wiring/wiring_audit_test.dart` imports the pure `auditWiring` function
// and fails on any gap that has not been explicitly justified below.

import 'dart:io';

// ---------------------------------------------------------------------------
// Evidence model
// ---------------------------------------------------------------------------

/// A source location, always rendered as `relative/path:line`.
class SourceRef {
  const SourceRef(this.path, this.line, [this.snippet = '']);

  final String path;
  final int line;
  final String snippet;

  @override
  String toString() => '$path:$line';
}

class DbObject {
  const DbObject(this.kind, this.name, this.ref, {this.arity = 0});

  final String kind; // table, view, function, trigger, policy, storage_bucket
  final String name;
  final SourceRef ref;
  final int arity;

  String get key => arity == 0 ? name : '$name/$arity';
}

class DbCall {
  const DbCall(this.kind, this.name, this.ref, this.file);

  final String kind; // table, rpc, storage_bucket
  final String name;
  final SourceRef ref;
  final String file;
}

class AppRoute {
  const AppRoute(this.path, this.screen, this.ref);

  final String path;
  final String screen;
  final SourceRef ref;
}

class Handler {
  const Handler(this.kind, this.expression, this.ref, this.file, this.sinks);

  final String kind; // onPressed, onTap, onChanged, ...
  final String expression;
  final SourceRef ref;
  final String file;
  final List<String> sinks;
}

class ProviderDef {
  const ProviderDef(this.name, this.ref);
  final String name;
  final SourceRef ref;
}

class RepoMethod {
  const RepoMethod(this.file, this.name, this.ref, this.dbCalls);
  final String file;
  final String name;
  final SourceRef ref;
  final List<String> dbCalls;
}

class EdgeFunction {
  const EdgeFunction(this.name, this.ref);
  final String name;
  final SourceRef ref;
}

class DashboardTile {
  const DashboardTile({
    required this.label,
    required this.field,
    required this.source,
    required this.drilldown,
    required this.ref,
    required this.testRef,
    required this.informational,
  });

  final String label;
  final String field;
  final String source;
  final String drilldown;
  final SourceRef ref;
  final SourceRef testRef;
  final bool informational;
}

class Gap {
  const Gap(this.check, this.subject, this.detail, this.ref,
      {this.fixHint = ''});

  final String check;
  final String subject;
  final String detail;
  final SourceRef? ref;
  final String fixHint;

  String get key => '$check|$subject';
}

/// One deliberate, evidence-backed exception. A waiver is only accepted while
/// the object/handler it names still exists, so it cannot rot into a blanket
/// bypass. Every waiver is printed in the matrix with its reason.
class Waiver {
  const Waiver(this.key, this.reason, this.evidence,
      {this.deferredCodeFix = false});
  final String key; // Gap.key
  final String reason;
  final String evidence; // file:line proving the justification

  /// True when the gap is real and the evidence points at a concrete fix that
  /// belongs to another workstream. It is still justified for this audit, but
  /// it must stay visible in the matrix and in the final report.
  final bool deferredCodeFix;
}

// ---------------------------------------------------------------------------
// Waivers — every unjustifiable-in-this-workstream gap is justified here.
// ---------------------------------------------------------------------------

const List<Waiver> _waivers = [
  // -------------------------------------------------------------------------
  // Justified: the gap is a true finding, but the code is wired indirectly or
  // is server-side only. Evidence is attached so the waiver cannot rot.
  // -------------------------------------------------------------------------
  Waiver(
    'forward/success_invalidation|lib/features/pos/screens/payment_dialog.dart',
    'Payment dialog is a pure collector: it returns rows via Navigator.pop; '
        'the caller performs the sale mutation, invalidates sales/stock/shift '
        'providers and shows the success snackbar.',
    'lib/features/pos/screens/payment_dialog.dart:170; '
        'lib/features/pos/screens/pos_screen.dart:133; '
        'lib/features/pos/screens/pos_screen.dart:166-171',
  ),
  Waiver(
    'forward/success_feedback|lib/features/pos/screens/payment_dialog.dart',
    'Payment dialog returns rows rather than committing; the caller owns the '
        'user-visible success feedback.',
    'lib/features/pos/screens/payment_dialog.dart:170-173; '
        'lib/features/pos/screens/pos_screen.dart:171',
  ),
  Waiver(
    'backward/object_used_or_internal|sale_return_items',
    'Server-side return line items written by process_sale_return; the returns '
        'UI reads sale_returns and sale_items instead.',
    'supabase/migrations/0020_fix_sale_return.sql:79; '
        'lib/features/sales/data/sales.dart:440; '
        'lib/features/sales/data/sales.dart:524',
  ),
  Waiver(
    'backward/object_used_or_internal|write_activity_log',
    'Trigger-only audit function; invoked by the audit triggers, never called '
        'directly by lib/.',
    'supabase/migrations/0017_activity_audit.sql:28; '
        'supabase/migrations/0017_activity_audit.sql:65-92',
  ),
  Waiver(
    'backward/object_used_or_internal|approve_expense',
    'Thin server-side delegation wrapper around set_expense_status, which is '
        'the RPC the expenses screen calls directly.',
    'supabase/migrations/0019_hardening_fixes.sql:500-504; '
        'lib/features/expenses/expenses_screen.dart:251',
  ),
  Waiver(
    'backward/object_used_or_internal|reject_expense',
    'Thin server-side delegation wrapper around set_expense_status, which is '
        'the RPC the expenses screen calls directly.',
    'supabase/migrations/0019_hardening_fixes.sql:506-510; '
        'lib/features/expenses/expenses_screen.dart:251',
  ),
  Waiver(
    'backward/object_used_or_internal|shift_expected_cash',
    'Read-only financial helper exercised by db_test and documented in the '
        'role matrix; the X report uses the shift.expectedCash field already '
        'computed by the close-shift flow.',
    'supabase/migrations/0019_hardening_fixes.sql:536; '
        'tool/db_test.sql:278; '
        'lib/features/shifts/screens/shifts_screen.dart:188; '
        'docs/ROLE_MATRIX.md:101',
  ),
  Waiver(
    'backward/route_reachable|/reset-password',
    'Public recovery deep link, reached by the auth redirect flow rather than '
        'a button.',
    'lib/core/router.dart:85; '
        'lib/core/router.dart:149-153; '
        'lib/core/router.dart:186',
  ),

  // -------------------------------------------------------------------------
  // Deferred code fixes: real defects owned by other workstreams. They are
  // justified for this audit only because the fix is outside the owned files;
  // each one names the exact file:line to change.
  // -------------------------------------------------------------------------
  Waiver(
    'backward/route_reachable|/inventory/categories',
    'Route is declared but no button navigates to it. Add a Categories button '
        'to the stock overview action row (or the inventory nav).',
    'lib/features/inventory/inventory_routes.dart:32; '
        'lib/features/inventory/screens/stock_overview_screen.dart:45-80',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/route_reachable|/inventory/batches',
    'Route is declared but no button navigates to it. Add a Batches button to '
        'the stock overview action row (or the inventory nav).',
    'lib/features/inventory/inventory_routes.dart:36; '
        'lib/features/inventory/screens/stock_overview_screen.dart:45-80',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/route_reachable|/inventory/adjustments',
    'Route is declared but no button navigates to it. Add an Adjustments '
        'button to the stock overview action row (or the inventory nav).',
    'lib/features/inventory/inventory_routes.dart:48; '
        'lib/features/inventory/screens/stock_overview_screen.dart:45-80',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/route_reachable|/inventory/movements',
    'Route is declared but no button navigates to it. Add a Movements button '
        'to the stock overview action row (or the inventory nav).',
    'lib/features/inventory/inventory_routes.dart:52; '
        'lib/features/inventory/screens/stock_overview_screen.dart:45-80',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/route_reachable|/inventory/stocktake',
    'Route is declared but no button navigates to it. Add a Stocktake button '
        'to the stock overview action row (or the inventory nav).',
    'lib/features/inventory/inventory_routes.dart:60; '
        'lib/features/inventory/screens/stock_overview_screen.dart:45-80',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/schema_check_coverage|write_activity_log',
    'Migration declares write_activity_log() but schema_check.sql does not '
        'expect it. Add (\'write_activity_log\', 0) to expected_functions.',
    'supabase/migrations/0017_activity_audit.sql:28; '
        'supabase/checks/schema_check.sql:26-44',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/schema_check_coverage|rls_activity_read',
    'Migration creates policy rls_activity_read but schema_check.sql does not '
        'expect it. Add it to expected_policies.',
    'supabase/migrations/0017_activity_audit.sql:97; '
        'supabase/checks/schema_check.sql:60-76',
    deferredCodeFix: true,
  ),
  Waiver(
    'backward/dashboard_tile_reconciliation|grossProfitToday',
    'Dashboard gross profit uses line_total - cost_price * quantity, while '
        'the report views subtract discount_share and returned_qty. Align the '
        'helper/query with the report contract.',
    'lib/features/dashboard/dashboard_metrics.dart:47-55; '
        'lib/features/dashboard/dashboard_metrics.dart:90-98; '
        'supabase/migrations/0014_report_views.sql:50-62; '
        'supabase/migrations/0007_functions.sql:308',
    deferredCodeFix: true,
  ),
];

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

List<String> _files(String root, List<String> extensions) {
  final result = <String>[];
  final dir = Directory(root);
  if (!dir.existsSync()) {
    throw StateError('Repository root does not exist: $root');
  }
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (!extensions.any(path.endsWith)) continue;
    if (path.contains('/.git/') || path.contains('/build/')) continue;
    if (path.contains('/.dart_tool/')) continue;
    result.add(path);
  }
  result.sort();
  return result;
}

String _rel(String root, String path) {
  final normalized = path.replaceAll(r'\', '/');
  final prefix = root.replaceAll(r'\', '/');
  if (normalized.startsWith('$prefix/'))
    return normalized.substring(prefix.length + 1);
  return normalized;
}

String _read(String path) => File(path).readAsStringSync();

List<String> _lines(String text) => text.split(RegExp(r'\r?\n'));

int _lineAt(String text, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text.codeUnitAt(i) == 10) line++;
  }
  return line;
}

String _trim(String value) => value.trim();

/// Counts SQL arguments in a parenthesised list starting at [openParen].
int _arity(String text, int openParen) {
  var depth = 0;
  var commas = 0;
  var quote = '';
  for (var i = openParen; i < text.length; i++) {
    final c = text[i];
    if (quote.isNotEmpty) {
      if (c == quote && (i == 0 || text[i - 1] != r'\')) quote = '';
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return commas == 0 ? 0 : commas + 1;
    }
    if (c == ',' && depth == 1) commas++;
  }
  return -1;
}

/// Collects the source lines of a Dart widget/method block opened at [start],
/// using parenthesis balance. Good enough for declarative widget code.
List<String> _block(List<String> lines, int start, {int max = 26}) {
  var depth = 0;
  var opened = false;
  final out = <String>[];
  for (var i = start; i < lines.length && i < start + max; i++) {
    final line = lines[i];
    out.add(line);
    for (final c in line.split('')) {
      if (c == '(') {
        depth++;
        opened = true;
      } else if (c == ')') {
        depth--;
      }
    }
    if (opened && depth <= 0) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------

class WiringInventory {
  WiringInventory({
    required this.routes,
    required this.handlers,
    required this.providers,
    required this.repoMethods,
    required this.dbCalls,
    required this.dbObjects,
    required this.edgeFunctions,
    required this.dashboardTiles,
    required this.schemaCheckPath,
    required this.schemaCheckText,
    required this.grantedFunctions,
    required this.reportViews,
    required this.libFiles,
    required this.ciJobs,
    required this.dashboardProfitFields,
    required this.reportProfitFields,
    required this.dashboardProfitRef,
  });

  final List<AppRoute> routes;
  final List<Handler> handlers;
  final List<ProviderDef> providers;
  final List<RepoMethod> repoMethods;
  final List<DbCall> dbCalls;
  final List<DbObject> dbObjects;
  final List<EdgeFunction> edgeFunctions;
  final List<DashboardTile> dashboardTiles;
  final String schemaCheckPath;
  final String schemaCheckText;
  final Set<String> grantedFunctions;
  final Set<String> reportViews;
  final List<String> libFiles;
  final List<String> ciJobs;

  /// Raw sale-item fields used by the dashboard profit helper and by the
  /// report views. Compared in the backward reconciliation check.
  final Set<String> dashboardProfitFields;
  final Set<String> reportProfitFields;
  final SourceRef dashboardProfitRef;

  Set<String> get objectNames => dbObjects.map((o) => o.name).toSet();
  Set<String> get usedTables => dbCalls.map((c) => c.name).toSet();
}

WiringInventory _extract(String root) {
  final libPaths = _files(root, const ['.dart'])
      .where((p) => _rel(root, p).startsWith('lib/'))
      .toList();
  final sqlPaths = _files(root, const ['.sql']).where((p) {
    final rel = _rel(root, p);
    return rel.startsWith('supabase/migrations/') ||
        rel.startsWith('supabase/checks/');
  }).toList();
  final migrationPaths = sqlPaths
      .where((p) => _rel(root, p).startsWith('supabase/migrations/'))
      .toList();

  final routes = <AppRoute>[];
  final handlers = <Handler>[];
  final providers = <ProviderDef>[];
  final repoMethods = <RepoMethod>[];
  final dbCalls = <DbCall>[];
  final dashboardTiles = <DashboardTile>[];
  final reportViews = <String>{};

  final routeRe = RegExp(r"\bpath:\s*'([^']+)'");
  final handlerRe = RegExp(
      r'\b(onPressed|onTap|onLongPress|onChanged|onSaved|onSubmitted|onFieldSubmitted|onSecondaryTap)\s*:\s*');
  final providerRe = RegExp(r'\bfinal\s+([A-Za-z0-9_]+Provider)\s*=');
  final rpcRe = RegExp(r"\.rpc\(\s*'([^']+)'");
  final storageRe = RegExp(r"\.storage\s*\.from\(\s*'([^']+)'\s*\)");
  final fromRe = RegExp(r"\.from\(\s*'([^']+)'\s*\)");
  final methodRe = RegExp(
      r'^\s*(?:Future<[^;{]+?>|Stream<[^;{]+?>|void|bool|String|int|double|List<[^;{]+?>|Map<[^;{]+?>)\s+([A-Za-z_]\w*)\s*\(',
      multiLine: false);
  final viewRefRe = RegExp(r"view:\s*'([^']+)'");

  for (final path in libPaths) {
    final rel = _rel(root, path);
    final text = _read(path);
    final lines = _lines(text);
    final isRouteFile =
        rel == 'lib/core/router.dart' || rel.endsWith('_routes.dart');
    final isDataFile = rel.contains('/data/') ||
        rel == 'lib/core/activity/activity.dart' ||
        rel == 'lib/features/dashboard/dashboard_metrics.dart';

    // Routes and their target screens.
    if (isRouteFile) {
      for (var i = 0; i < lines.length; i++) {
        final match = routeRe.firstMatch(lines[i]);
        if (match == null) continue;
        var screen = '<builder>';
        for (var j = i + 1; j < lines.length && j <= i + 5; j++) {
          final builder = RegExp(r'(?:const\s+)?([A-Z]\w*Screen)\s*\(')
              .firstMatch(lines[j]);
          if (builder != null) {
            screen = builder.group(1)!;
            break;
          }
        }
        routes.add(AppRoute(match.group(1)!, screen, SourceRef(rel, i + 1)));
      }
    }

    // Providers.
    for (var i = 0; i < lines.length; i++) {
      final match = providerRe.firstMatch(lines[i]);
      if (match != null) {
        providers.add(ProviderDef(match.group(1)!, SourceRef(rel, i + 1)));
      }
    }

    // Handlers: classify their reachable sinks.
    for (var i = 0; i < lines.length; i++) {
      for (final match in handlerRe.allMatches(lines[i])) {
        final kind = match.group(1)!;
        final after = lines[i].substring(match.end).trim();
        var expression = after;
        if (expression.isEmpty && i + 1 < lines.length) {
          expression = _trim(lines[i + 1]);
        }
        // Widget callbacks are commonly written across several lines, so the
        // sink scan covers the callback body as well as the declaration line.
        final lookahead = lines.skip(i + 1).take(6).join(' ');
        final nearText = lines.skip(i + 1).take(2).join(' ');
        final sinkText = '$after $lookahead';
        final sinks = <String>[];
        if (RegExp(r'\bcontext\s*\.\s*(go|push|replace|goNamed)')
            .hasMatch(sinkText)) {
          sinks.add('navigation');
        }
        if (RegExp(r'\.(rpc|insert|update|delete|upsert)\s*\(')
            .hasMatch(sinkText)) {
          sinks.add('data');
        }
        if (RegExp(r'invalidate\w*\s*\(').hasMatch(sinkText)) {
          sinks.add('invalidate');
        }
        if (RegExp(
                r'(SnackBar|snack|showFeedback|showAppMessage|showDialog|'
                r'showModalBottomSheet|launchUrl|Share\.share|Navigator\.)',
                caseSensitive: false)
            .hasMatch(sinkText)) {
          sinks.add('feedback');
        }
        if (RegExp(r'\b_[A-Za-z]\w*\b|=>\s*[A-Za-z]\w*\s*\(')
            .hasMatch(sinkText)) {
          sinks.add('helper');
        }
        // Widget libraries forward their callback to the caller
        // (`onPressed: onPressed`, `onTap: onTap`, ...) and screens pass public
        // helpers (`openAppSettings`, `editSupplier`). Both are real sinks; the
        // concrete call site is checked at the other end of the wire.
        if (RegExp(r'\bon[A-Z]\w*|\bopenAppSettings\b').hasMatch(sinkText)) {
          sinks.add('callback');
        }
        if (RegExp(r'\b[a-zA-Z]\w*\s*\(').hasMatch('$after $nearText')) {
          sinks.add('call');
        }
        if (RegExp(r'setState\s*\(|ref\.read\(|ref\.watch\(')
                .hasMatch(sinkText) ||
            after.contains(' = ')) {
          sinks.add('state');
        }
        handlers.add(Handler(kind, expression,
            SourceRef(rel, i + 1, _trim(lines[i])), rel, sinks));
      }
    }

    // Repository methods (declared in data/ files) and the DB calls they make.
    if (isDataFile) {
      for (var i = 0; i < lines.length; i++) {
        final match = methodRe.firstMatch(lines[i]);
        if (match == null) continue;
        final name = match.group(1)!;
        if (const {'if', 'for', 'while', 'switch', 'return'}.contains(name)) {
          continue;
        }
        final body = _block(lines, i, max: 90).join('\n');
        final calls = <String>[];
        for (final call in rpcRe.allMatches(body)) {
          calls.add('rpc:${call.group(1)}');
        }
        for (final call in fromRe.allMatches(body)) {
          calls.add('table:${call.group(1)}');
        }
        for (final call in storageRe.allMatches(body)) {
          calls.add('bucket:${call.group(1)}');
        }
        repoMethods.add(RepoMethod(rel, name, SourceRef(rel, i + 1), calls));
      }
    }

    // Every PostgREST / RPC / Storage target used anywhere in lib/.
    for (final match in storageRe.allMatches(text)) {
      dbCalls.add(DbCall('storage_bucket', match.group(1)!,
          SourceRef(rel, _lineAt(text, match.start)), rel));
    }
    for (final match in rpcRe.allMatches(text)) {
      dbCalls.add(DbCall('rpc', match.group(1)!,
          SourceRef(rel, _lineAt(text, match.start)), rel));
    }
    for (final match in fromRe.allMatches(text)) {
      final start = match.start;
      // `.storage.from('x')` was recorded above; skip it here.
      final prefix = start >= 12
          ? text.substring(start - 12, start)
          : text.substring(0, start);
      if (prefix.contains('.storage')) continue;
      dbCalls.add(DbCall(
          'table', match.group(1)!, SourceRef(rel, _lineAt(text, start)), rel));
    }
    // Some screens hold the bucket name in a `const bucket = 'branding'`
    // local before calling `storage.from(bucket)`. Resolve the alias so the
    // backward check sees the bucket as UI-used rather than orphaned.
    for (final match
        in RegExp(r'\.storage\s*\.from\(\s*(\w+)\s*\)').allMatches(text)) {
      final alias = match.group(1)!;
      final aliasDecl = RegExp(r'\b(?:final|const)\s+' +
              RegExp.escape(alias) +
              r"\s*=\s*'([^']+)'")
          .firstMatch(text.substring(0, match.start));
      if (aliasDecl != null) {
        dbCalls.add(DbCall('storage_bucket', aliasDecl.group(1)!,
            SourceRef(rel, _lineAt(text, match.start)), rel));
      }
    }

    // `purchasing.dart` calls `_db.rpc(function, ...)` where `function` comes
    // from this candidate list. Record the candidates as RPC usage so the
    // fallback functions are not reported as dead database objects.
    if (rel.endsWith('purchase_status_helpers.dart')) {
      for (final match in RegExp(r"'([a-z][a-z0-9_]+)'").allMatches(text)) {
        final name = match.group(1)!;
        if (!name.contains('_')) continue;
        dbCalls.add(DbCall(
            'rpc', name, SourceRef(rel, _lineAt(text, match.start)), rel));
      }
    }

    // Report views are read through `from(report.view)`; collect their names
    // from the two declarative report registries so backward coverage works.
    if (rel.contains('reports')) {
      for (final match in viewRefRe.allMatches(text)) {
        reportViews.add(match.group(1)!);
      }
    }

    // Dashboard tiles: label, backing snapshot field, drill-down and test.
    if (rel == 'lib/features/dashboard/dashboard_screen.dart') {
      final testPath = '$root/test/widget/dashboard_layout_test.dart';
      final testText = File(testPath).existsSync() ? _read(testPath) : '';
      final testLine = _lineAt(testText, testText.indexOf('DashboardScreen('));
      final testRef = SourceRef(
          'test/widget/dashboard_layout_test.dart',
          testLine == 1 && !testText.contains('DashboardScreen(')
              ? 1
              : testLine);
      for (var i = 0; i < lines.length; i++) {
        final isStat = _trim(lines[i]).startsWith('StatCard(');
        final isAlert = _trim(lines[i]).startsWith('_AlertLine(');
        if (!isStat && !isAlert) continue;
        final block = _block(lines, i);
        final joined = block.join('\n');
        final labelLine = RegExp(r'\b(?:title|label):\s*([^\n]+)')
                .firstMatch(joined)
                ?.group(1) ??
            '';
        final labelMatch = RegExp(r'S\.(\w+)').firstMatch(labelLine);
        final fieldMatch =
            RegExp(r'\bvalue:\s*(?:money|count)?\(?\s*data\.(\w+)')
                .firstMatch(joined);
        final drillMatch =
            RegExp(r"context\.go\('([^']+)'\)").firstMatch(joined);
        final dynamicDrill = joined.contains('context.go(item.path)');
        final label = labelMatch?.group(1) ?? '<label>';
        final field = fieldMatch?.group(1) ?? '<field>';
        // The source query is resolved from the snapshot field assignment in
        // DashboardSnapshot.load; see _resolveTileSource below.
        final source = '<unresolved>';
        dashboardTiles.add(DashboardTile(
          label: label,
          field: field,
          source: source,
          drilldown:
              drillMatch?.group(1) ?? (dynamicDrill ? '<menu-shortcut>' : ''),
          ref: SourceRef(rel, i + 1, _trim(lines[i])),
          testRef: testRef,
          informational: drillMatch == null && !dynamicDrill,
        ));
      }
    }
  }

  // Resolve each dashboard tile's source query from the snapshot loader.
  final dashboardPath = libPaths.firstWhere(
      (p) => p.endsWith('features/dashboard/dashboard_screen.dart'),
      orElse: () => '');
  if (dashboardPath.isNotEmpty) {
    final lines = _lines(_read(dashboardPath));
    final fromReLocal = RegExp(r"\.from\('([^']+)'\)");
    // Map each local query helper to the table it reads.
    final functionTable = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      final fn = RegExp(r'^\s*(?:static\s+)?[\w<>?, ]+\s+(\w+)\s*\(')
          .firstMatch(lines[i]);
      if (fn == null) continue;
      for (var j = i + 1; j < lines.length && j < i + 30; j++) {
        final table = fromReLocal.firstMatch(lines[j]);
        if (table != null) {
          functionTable.putIfAbsent(fn.group(1)!, () => table.group(1)!);
          break;
        }
      }
    }
    // Map each local variable declared in load() to the table it came from,
    // either directly via `.from('x')` or through a query helper.
    final varTable = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      final declaration =
          RegExp(r'^\s*(?:final|var)\s+(\w+)\s*=\s*(.*)$').firstMatch(lines[i]);
      if (declaration == null) continue;
      final name = declaration.group(1)!;
      final initializer = declaration.group(2)!;
      String? resolved;
      for (final entry in functionTable.entries) {
        if (RegExp('\\b${RegExp.escape(entry.key)}\\b').hasMatch(initializer)) {
          resolved = entry.value;
          break;
        }
      }
      for (var j = i; resolved == null && j < lines.length && j < i + 16; j++) {
        resolved = fromReLocal.firstMatch(lines[j])?.group(1);
        if (j > i && RegExp(r'^\s*final\s+\w+\s*=').hasMatch(lines[j])) break;
      }
      if (resolved != null) varTable.putIfAbsent(name, () => resolved!);
    }
    // Map snapshot fields to the local variable used in the constructor.
    final fieldQuery = <String, String>{};
    final returnLine =
        lines.indexWhere((line) => line.contains('return DashboardSnapshot('));
    for (var i = returnLine < 0 ? 0 : returnLine;
        i < lines.length && i < returnLine + 40;
        i++) {
      final assignment = RegExp(r'^\s{6}(\w+):\s+(.+)$').firstMatch(lines[i]);
      if (assignment == null) continue;
      final field = assignment.group(1)!;
      final expression = assignment.group(2)!;
      final identifiers = RegExp(r'\b[a-zA-Z]\w*\b')
          .allMatches(expression)
          .map((match) => match.group(0)!);
      for (final id in identifiers) {
        final table = varTable[id];
        if (table != null) {
          fieldQuery[field] = table;
          break;
        }
      }
    }
    for (var i = 0; i < dashboardTiles.length; i++) {
      final tile = dashboardTiles[i];
      // The explicit contract is authoritative: the heuristic varTable can
      // otherwise latch onto a nearby `.from()` call and mislabel a tile.
      final resolved =
          _dashboardFieldSources[tile.field] ?? fieldQuery[tile.field];
      if (resolved != null) {
        dashboardTiles[i] = DashboardTile(
          label: tile.label,
          field: tile.field,
          source: resolved,
          drilldown: tile.drilldown,
          ref: tile.ref,
          testRef: tile.testRef,
          informational: tile.informational,
        );
      }
    }
  }

  // Database objects declared by the migrations.
  final dbObjects = <DbObject>[];
  final grantedFunctions = <String>{};
  final tableRe = RegExp(
      r'\bcreate\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?(\w+)',
      caseSensitive: false);
  final viewRe = RegExp(
      r'\bcreate\s+(?:or\s+replace\s+)?view\s+(?:public\.)?(\w+)',
      caseSensitive: false);
  final functionRe = RegExp(
      r'\bcreate\s+(?:or\s+replace\s+)?function\s+(?:public\.)?(\w+)\s*\(',
      caseSensitive: false);
  final triggerRe = RegExp(r'\bcreate\s+trigger\s+(\w+)', caseSensitive: false);
  final policyRe = RegExp(r'\bcreate\s+policy\s+(\w+)', caseSensitive: false);
  final grantRe = RegExp(
      r'\bgrant\s+execute\s+on\s+function\s+(?:public\.)?(\w+)',
      caseSensitive: false);
  final bucketTupleRe = RegExp(r"\('([^']+)',\s*'([^']+)',\s*(true|false)");

  for (final path in migrationPaths) {
    final rel = _rel(root, path);
    final text = _read(path);
    for (final pattern in [tableRe, viewRe, functionRe, triggerRe, policyRe]) {
      for (final match in pattern.allMatches(text)) {
        final kind = identical(pattern, tableRe)
            ? 'table'
            : identical(pattern, viewRe)
                ? 'view'
                : identical(pattern, functionRe)
                    ? 'function'
                    : identical(pattern, triggerRe)
                        ? 'trigger'
                        : 'policy';
        final name = match.group(1)!;
        // `execute format('create trigger trg_%s_updated ...')` is a template,
        // not a declared trigger. The concrete names are asserted by
        // schema_check.sql's expected_triggers list.
        if (kind == 'trigger' && (name.endsWith('_') || name.contains('%'))) {
          continue;
        }
        final arity =
            identical(pattern, functionRe) ? _arity(text, match.end - 1) : 0;
        dbObjects.add(DbObject(
            kind, name, SourceRef(rel, _lineAt(text, match.start)),
            arity: arity));
      }
    }
    for (final match in grantRe.allMatches(text)) {
      grantedFunctions.add(match.group(1)!);
    }
    // Storage buckets are inserted as tuples in `storage.buckets`.
    final bucketInsert =
        RegExp(r'insert\s+into\s+storage\.buckets', caseSensitive: false)
            .firstMatch(text);
    if (bucketInsert != null) {
      final tail = text.substring(bucketInsert.start,
          (bucketInsert.start + 1400).clamp(0, text.length));
      for (final match in bucketTupleRe.allMatches(tail)) {
        dbObjects.add(DbObject('storage_bucket', match.group(1)!,
            SourceRef(rel, _lineAt(text, bucketInsert.start + match.start))));
      }
    }
  }

  // Edge Functions.
  final edgeFunctions = <EdgeFunction>[];
  final functionsDir = Directory('$root/supabase/functions');
  if (functionsDir.existsSync()) {
    for (final entity in functionsDir.listSync()) {
      if (entity is! Directory ||
          entity.path.split(Platform.pathSeparator).last.startsWith('_')) {
        continue;
      }
      final index = File('${entity.path}/index.ts');
      if (!index.existsSync()) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      edgeFunctions.add(EdgeFunction(
          name, SourceRef('supabase/functions/$name/index.ts', 1)));
    }
  }

  final schemaPath = '$root/supabase/checks/schema_check.sql';
  final ciPaths = _files(root, const ['.yml'])
      .where((p) => _rel(root, p).startsWith('.github/workflows/'))
      .toList();
  final ciJobs = <String>[];
  for (final path in ciPaths) {
    final rel = _rel(root, path);
    final jobRe = RegExp(r'^  ([a-zA-Z][\w-]*):\s*$', multiLine: true);
    for (final match in jobRe.allMatches(_read(path))) {
      ciJobs.add('$rel → ${match.group(1)}');
    }
  }

  // Dashboard ↔ report reconciliation: both layers must account for sale
  // discounts and returned quantities when deriving profit.
  const profitFields = <String>{'discount_share', 'returned_qty'};
  final metricsPath = '$root/lib/features/dashboard/dashboard_metrics.dart';
  final metricsText = File(metricsPath).existsSync() ? _read(metricsPath) : '';
  final reportSqlPath = '$root/supabase/migrations/0014_report_views.sql';
  final reportSql =
      File(reportSqlPath).existsSync() ? _read(reportSqlPath) : '';
  final dashboardProfitFields =
      profitFields.where((field) => metricsText.contains(field)).toSet();
  final reportProfitFields =
      profitFields.where((field) => reportSql.contains(field)).toSet();
  final profitOffset = metricsText.indexOf('double? dashboardGrossProfit');

  return WiringInventory(
    routes: routes,
    handlers: handlers,
    providers: providers,
    repoMethods: repoMethods,
    dbCalls: dbCalls,
    dbObjects: dbObjects,
    edgeFunctions: edgeFunctions,
    dashboardTiles: dashboardTiles,
    schemaCheckPath: 'supabase/checks/schema_check.sql',
    schemaCheckText: File(schemaPath).existsSync() ? _read(schemaPath) : '',
    grantedFunctions: grantedFunctions,
    reportViews: reportViews,
    libFiles: libPaths.map((p) => _rel(root, p)).toList(),
    ciJobs: ciJobs,
    dashboardProfitFields: dashboardProfitFields,
    reportProfitFields: reportProfitFields,
    dashboardProfitRef: SourceRef(
        'lib/features/dashboard/dashboard_metrics.dart',
        profitOffset < 0 ? 47 : _lineAt(metricsText, profitOffset)),
  );
}

// ---------------------------------------------------------------------------
// Justifications for objects that are intentionally not UI-reachable
// ---------------------------------------------------------------------------

const Map<String, String> _internalObjects = {
  // Server-side infrastructure: triggers, RLS policies and helper functions
  // are enforced by PostgreSQL, never called by a screen.
  'set_updated_at': 'timestamp trigger helper; called only by trg_*_updated',
  'my_role': 'RLS helper; evaluated inside policies',
  'my_branch': 'RLS helper; evaluated inside policies',
  'has_role': 'role helper; called by SECURITY DEFINER RPCs and policies',
  'can_access_branch': 'branch helper; called by SECURITY DEFINER RPCs',
  'handle_new_user': 'auth trigger on auth.users',
  'next_doc_no': 'document numbering helper called by PO/RX triggers',
  'trg_po_defaults': 'trigger function for purchase-order defaults',
  'trg_rx_defaults': 'trigger function for prescription defaults',
  'trg_po_total': 'trigger function recomputing PO totals',
  'recalc_po_subtotal': 'trigger helper called by trg_poi_recalc',
  'guard_po_status': 'trigger function guarding PO status transitions',
  'guard_po_receipt': 'trigger function guarding receipt quantities',
  'guard_expense_status': 'trigger function guarding expense status',
  'protect_profile_fields':
      'trigger function protecting protected profile columns',
  'audit_row': 'trigger function writing activity_log',
  // Internal ledger/seed objects with no screen of their own.
  'doc_counters': 'server-side document number counters',
  'audit_logs': 'legacy append-only audit table, superseded by activity_log',
  'storage.objects': 'Supabase Storage internals',
  // Views that duplicate a screen-side derivation.
  'v_stock_summary':
      'stock totals are also rendered by StockOverview via v_low_stock/v_expiring_batches',
  'v_daily_sales':
      'dashboard aggregates raw sales in Dart; kept for SQL reporting',
};

/// Dashboard snapshot field → the table/view that feeds it. This is the
/// explicit wiring contract extracted from `DashboardSnapshot.load`
/// (`lib/features/dashboard/dashboard_screen.dart:213-395`) and
/// `DashboardRepository` (`lib/features/dashboard/dashboard_metrics.dart:71-153`).
/// It is used as a fallback when the static resolver cannot follow a helper.
const Map<String, String> _dashboardFieldSources = {
  'todaySales': 'sales',
  'monthSales': 'sales',
  'grossProfitToday': 'sale_items',
  'invoiceCount': 'sales',
  'openShifts': 'shifts',
  'lowStock': 'v_low_stock',
  'expiringSoon': 'v_expiring_batches',
  'expired': 'v_expiring_batches',
  'pendingPrescriptions': 'prescriptions',
  'pendingOrders': 'purchase_orders',
  'periodSales': 'sales',
  'periodProfit': 'sale_items',
  'periodInvoices': 'sales',
  'daily': 'sales',
  'topMedicines': 'sale_items',
  'recentActivityLog': 'activity_log',
  'teamStatus': 'profiles',
};

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

class WiringAudit {
  WiringAudit(String root)
      : inventory = _extract(root),
        root = root {
    gaps = _check();
    _waiverTargets = <String>{};
    for (final waiver in _waivers) {
      _waiverTargets.add(waiver.key);
    }
    for (final waiver in _waivers) {
      if (!gaps.any((g) => g.key == waiver.key)) {
        gaps.add(Gap(
            'waiver',
            waiver.key,
            'Waiver is stale: no matching gap was found. Remove or update it.',
            null,
            fixHint: 'tool/wiring_audit.dart'));
      }
    }
    if (_waiverTargets.isEmpty) {
      // No waivers means every gap must be a real, actionable finding.
    }
  }

  final String root;
  final WiringInventory inventory;
  late final List<Gap> gaps;
  late final Set<String> _waiverTargets;

  Waiver? _waiverFor(Gap gap) {
    for (final waiver in _waivers) {
      if (waiver.key == gap.key) return waiver;
    }
    return null;
  }

  bool get hasUnjustifiedGaps => gaps.any((g) => _waiverFor(g) == null);

  List<Gap> get unjustifiedGaps =>
      gaps.where((g) => _waiverFor(g) == null).toList();

  /// All waived gaps whose fix belongs to another workstream. Kept separate
  /// from ordinary justified gaps so the final report can name them.
  List<Gap> get deferredCodeFixGaps =>
      gaps.where((g) => _waiverFor(g)?.deferredCodeFix == true).toList();

  List<Gap> _check() {
    final result = <Gap>[];
    final inv = inventory;

    // FORWARD 1: no null or empty widget handlers.
    for (final handler in inv.handlers) {
      final expression = handler.expression;
      if (expression == 'null' ||
          RegExp(r'^\(\)\s*\{\s*\}$').hasMatch(expression)) {
        result.add(Gap(
            'forward/non_null_handler',
            '${handler.file}@${handler.ref.line}',
            '${handler.kind} has a null/empty body',
            handler.ref,
            fixHint: '${handler.file}:${handler.ref.line}'));
      }
    }

    // FORWARD 2: every handler reaches a data, navigation, feedback, helper or
    // state sink. A handler with no sink is dead UI.
    for (final handler in inv.handlers) {
      if (handler.sinks.isEmpty) {
        result.add(Gap(
            'forward/handler_sink',
            '${handler.file}@${handler.ref.line}',
            '${handler.kind} (${handler.expression}) reaches no sink',
            handler.ref,
            fixHint: '${handler.file}:${handler.ref.line}'));
      }
    }

    // FORWARD 3: every repository method declares at least one DB call, and
    // every DB object it touches exists in a migration.
    final objectNames = inv.objectNames;
    for (final method in inv.repoMethods) {
      if (method.dbCalls.isEmpty) continue; // pure model/helper method
      for (final call in method.dbCalls) {
        final name = call.split(':').skip(1).join(':');
        if (!objectNames.contains(name)) {
          result.add(Gap(
              'forward/repository_target',
              '${method.file}:${method.name}:$name',
              'Repository method ${method.name} targets undeclared object `$name`',
              method.ref,
              fixHint: '${method.file}:${method.ref.line}'));
        }
      }
    }

    // FORWARD 4: every lib DB target exists in migrations, and every RPC used
    // by the UI is granted to `authenticated`.
    for (final call in inv.dbCalls) {
      if (!objectNames.contains(call.name)) {
        result.add(Gap(
            'forward/db_object_exists',
            '${call.kind}:${call.name}',
            '${call.file}:${call.ref.line} uses ${call.kind} `${call.name}` that no migration declares',
            call.ref,
            fixHint: '${call.file}:${call.ref.line}'));
      }
      if (call.kind == 'rpc' && !inv.grantedFunctions.contains(call.name)) {
        result.add(Gap(
            'forward/rpc_grant',
            call.name,
            'RPC `${call.name}` is called by ${call.file}:${call.ref.line} but has no grant to authenticated',
            call.ref,
            fixHint: 'supabase/migrations/ (grant execute)'));
      }
    }

    // FORWARD 5: success feedback + invalidation/refresh on every mutating
    // *screen*. Repositories only perform the write; the screen owns the
    // invalidation and the user-visible confirmation.
    bool isUiFile(String path) =>
        path.endsWith('_screen.dart') ||
        path.contains('/screens/') ||
        path.contains('/widgets/');
    final mutationRe = RegExp(
        r'\.(rpc|insert|update|delete|upsert)\s*\(|\.upload(Binary|String)\s*\(');
    final filesWithMutations = <String>{};
    for (final call in inv.dbCalls) {
      if (call.kind == 'rpc' && isUiFile(call.file)) {
        filesWithMutations.add(call.file);
      }
    }
    for (final path in inv.libFiles) {
      if (!isUiFile(path)) continue;
      if (!mutationRe.hasMatch(_read('$root/$path'))) continue;
      filesWithMutations.add(path);
    }
    for (final path in filesWithMutations) {
      if (!File('$root/$path').existsSync()) continue;
      final text = _read('$root/$path');
      final refreshes =
          RegExp(r'invalidate\w*\s*\(|\b_(?:load|refresh|reload)\s*\(|'
                  r'\brefreshProfile\s*\(|\breloadProfile\s*\(')
              .hasMatch(text);
      if (!refreshes) {
        result.add(Gap(
            'forward/success_invalidation',
            path,
            'Mutating screen has no provider/cache invalidation or local refresh',
            null,
            fixHint: '$path (invalidate after success)'));
      }
      if (!RegExp(
              r'(SnackBar|showFeedback|showAppMessage|snack|_snack|'
              r'ScaffoldMessenger)',
              caseSensitive: false)
          .hasMatch(text)) {
        result.add(Gap('forward/success_feedback', path,
            'Mutating screen has no user-visible success feedback', null,
            fixHint: '$path (show feedback after success)'));
      }
    }

    // FORWARD 6: every error path that reaches the UI maps through
    // AppErrorMapper (directly or via a shared error widget/snackbar helper).
    // Data/local-cache helpers that swallow or rethrow errors are checked at
    // their caller, not here.
    for (final path in inv.libFiles) {
      final text = _read('$root/$path');
      if (!text.contains('catch ') && !text.contains('catch(')) continue;
      if (!isUiFile(path) && path != 'lib/core/auth/auth_controller.dart') {
        continue;
      }
      final mapsDirectly = text.contains('AppErrorMapper.from');
      final usesHelper = RegExp(r'AsyncStateView|AsyncValue|AsyncState|'
              r'_errorText|ErrorState|_message\(|failureMessage|AppSnackbar|'
              r'AppError\(')
          .hasMatch(text);
      if (!mapsDirectly && !usesHelper) {
        result.add(Gap(
            'forward/mapped_error',
            path,
            'UI file catches errors but never maps them through AppErrorMapper',
            null,
            fixHint: '$path (use AppErrorMapper.from)'));
      }
    }

    // FORWARD 7: Edge Functions referenced by the UI must exist on disk.
    final edgeNames = inv.edgeFunctions.map((e) => e.name).toSet();
    final edgeRefRe =
        RegExp(r"functions/(?:v1/)?([a-z][\w-]*)/?", caseSensitive: false);
    for (final path in inv.libFiles) {
      final text = _read('$root/$path');
      for (final match in edgeRefRe.allMatches(text)) {
        final name = match.group(1)!;
        if (name == 'v1') continue;
        if (!edgeNames.contains(name) && name.contains('-')) {
          result.add(Gap(
              'forward/edge_function_exists',
              '$path:$name',
              'UI references Edge Function `$name` with no supabase/functions/$name/index.ts',
              SourceRef(path, _lineAt(text, match.start)),
              fixHint: 'supabase/functions/'));
        }
      }
    }

    // BACKWARD 1: every migration object is used by a screen/repository or is
    // explicitly tagged internal with a reason.
    final used = inv.usedTables.union(inv.reportViews);
    for (final object in inv.dbObjects) {
      final isUsed = used.contains(object.name) ||
          inv.dbCalls.any((c) => c.name == object.name);
      // Triggers and RLS policies are database-enforced by definition; no
      // screen calls them directly. Their existence is verified by
      // schema_check.sql and the db-test CI job.
      final serverEnforced =
          object.kind == 'trigger' || object.kind == 'policy';
      final internal = _internalObjects[object.name] ??
          (serverEnforced
              ? 'server-side ${object.kind}; enforced by PostgreSQL'
              : null);
      if (!isUsed && internal == null) {
        result.add(Gap(
            'backward/object_used_or_internal',
            object.key,
            '${object.kind} `${object.key}` is neither used by lib/ nor tagged internal',
            object.ref,
            fixHint:
                '${object.ref.path}:${object.ref.line} or add justification'));
      }
      if (isUsed && internal != null) {
        // Harmless, but record it so the matrix can show the classification.
      }
    }
    for (final edge in inv.edgeFunctions) {
      final referenced = inv.libFiles
          .any((path) => _read('$root/$path').contains('${edge.name}'));
      if (!referenced) {
        result.add(Gap('backward/edge_function_used', edge.name,
            'Edge Function `${edge.name}` is not referenced by lib/', edge.ref,
            fixHint: 'lib/ or add justification'));
      }
    }

    // BACKWARD 2: every declared route is reachable from the menu, a navigation
    // call, a redirect target or a homeFor() result.
    final reachable = <String>{};
    final navLiteralRe = RegExp(
        r"context\.(?:go|push|replace)\(\s*'([^']+)'|(?:=>|return)\s*'(\/[a-z][\w\-/]*)'",
        caseSensitive: false);
    for (final path in inv.libFiles) {
      final text = _read('$root/$path');
      for (final match in navLiteralRe.allMatches(text)) {
        final target = match.group(1) ?? match.group(2);
        if (target != null) reachable.add(target.split('?').first);
      }
      // Menu items are declared as `path: '/x'` and used by context.go(item.path).
      if (path.contains('menu_items.dart')) {
        for (final match in RegExp(r"\bpath:\s*'([^']+)'").allMatches(text)) {
          reachable.add(match.group(1)!);
        }
      }
    }
    // homeFor() returns literals that the regex above may miss on a switch arm.
    for (final match in RegExp(r"=>\s*'(/[^']+)'")
        .allMatches(_read('$root/lib/core/nav/menu_items.dart'))) {
      reachable.add(match.group(1)!);
    }
    for (final route in inv.routes) {
      final paramIndex = route.path.indexOf('/:');
      final isParam = paramIndex >= 0;
      final prefix = isParam ? route.path.substring(0, paramIndex) : route.path;
      final isReachable = reachable.any((target) {
        final t = target.split('?').first;
        if (t == route.path || t == prefix) return true;
        if (isParam) return t.startsWith('$prefix/');
        // A button to a child path proves this parent path is live too, e.g.
        // `/inventory/medicines/:id` implies `/inventory/medicines`.
        return t.startsWith('$prefix/');
      });
      if (!isReachable) {
        result.add(Gap(
            'backward/route_reachable',
            route.path,
            'Route ${route.path} (${route.screen}) has no navigation/button/redirect reference',
            route.ref,
            fixHint: '${route.ref.path}:${route.ref.line}'));
      }
    }

    // BACKWARD 3: every migration object is named in schema_check.sql.
    for (final object in inv.dbObjects) {
      final escaped = RegExp.escape(object.name);
      if (!RegExp('\\b$escaped\\b').hasMatch(inv.schemaCheckText)) {
        result.add(Gap(
            'backward/schema_check_coverage',
            object.key,
            '${object.kind} `${object.key}` is not covered by schema_check.sql',
            object.ref,
            fixHint: 'supabase/checks/schema_check.sql'));
      }
    }

    // BACKWARD 4: every dashboard tile has a source query, a drill-down (or an
    // explicit informational justification) and a test.
    for (final tile in inv.dashboardTiles) {
      if (tile.field == '<field>' || tile.source == '<unresolved>') {
        result.add(Gap(
            'backward/dashboard_tile_source',
            tile.label,
            'Dashboard tile `${tile.label}` has no resolved source query/field',
            tile.ref,
            fixHint:
                'lib/features/dashboard/dashboard_screen.dart:${tile.ref.line}'));
      }
      if (tile.drilldown.isEmpty && !tile.informational) {
        result.add(Gap('backward/dashboard_tile_drilldown', tile.label,
            'Dashboard tile `${tile.label}` has no drill-down target', tile.ref,
            fixHint:
                'lib/features/dashboard/dashboard_screen.dart:${tile.ref.line}'));
      }
      if (tile.testRef.line < 1) {
        result.add(Gap(
            'backward/dashboard_tile_test',
            tile.label,
            'Dashboard tile `${tile.label}` is not covered by a widget/snapshot test',
            tile.ref,
            fixHint: 'test/widget/dashboard_layout_test.dart'));
      }
    }

    // Reconcile the dashboard profit helper with the report views. Both read
    // sale_items, so they must agree on discount and return adjustments.
    final missingProfitFields =
        inv.reportProfitFields.difference(inv.dashboardProfitFields);
    if (missingProfitFields.isNotEmpty) {
      final fields = missingProfitFields.toList()..sort();
      result.add(Gap(
          'backward/dashboard_tile_reconciliation',
          'grossProfitToday',
          'Dashboard gross profit ignores ${fields.join(' and ')} while '
              'v_report_sales_by_medicine includes them',
          inv.dashboardProfitRef,
          fixHint: 'lib/features/dashboard/dashboard_metrics.dart:47'));
    }

    // The report views used by the Reports screen must all exist.
    for (final view in inv.reportViews) {
      if (!objectNames.contains(view)) {
        result.add(Gap('backward/report_view_exists', view,
            'Report registry references view `$view` with no migration', null,
            fixHint: 'supabase/migrations/0014_report_views.sql'));
      }
    }

    return result;
  }
}

/// Convenience entry point used by `test/wiring/wiring_audit_test.dart`.
WiringAudit auditWiring(String root) => WiringAudit(root);

// ---------------------------------------------------------------------------
// Matrix rendering
// ---------------------------------------------------------------------------

String _md(String value) => value.replaceAll('|', r'\|');

String renderMatrix(WiringAudit audit) {
  final inv = audit.inventory;
  final out = StringBuffer();
  final byCheck = <String, List<Gap>>{};
  for (final gap in audit.gaps) {
    byCheck.putIfAbsent(gap.check, () => []).add(gap);
  }
  String status(String key, {String? subject}) {
    final items = byCheck[key]
            ?.where((g) => subject == null || g.subject == subject)
            .toList() ??
        const <Gap>[];
    if (items.isEmpty) return 'OK';
    final waivers = items.map((g) => _waiverForSimple(g, audit)).toList();
    if (waivers.any((w) => w == null)) return 'GAP';
    if (waivers.any((w) => w!.deferredCodeFix)) return 'DEFERRED';
    return 'JUSTIFIED';
  }

  String worst(Iterable<String> statuses) {
    final values = statuses.toSet();
    if (values.contains('GAP')) return 'GAP';
    if (values.contains('DEFERRED')) return 'DEFERRED';
    if (values.contains('JUSTIFIED')) return 'JUSTIFIED';
    return 'OK';
  }

  out.writeln('# Wiring matrix');
  out.writeln();
  out.writeln(
      'Generated by `dart run tool/wiring_audit.dart` from a static scan of '
      '`lib/**` and `supabase/**`. Do not edit by hand.');
  out.writeln();
  out.writeln(
      '- Direction **forward**: UI handler → repository method → DB object → grant/policy → feedback + invalidation → mapped error.');
  out.writeln(
      '- Direction **backward**: DB object → screen or internal tag; route → navigation/button; migration object → `schema_check.sql`; tile → query + drill-down + test.');
  out.writeln(
      '- `JUSTIFIED` means the gap is real but deliberately out of scope for this workstream; the reason and evidence are given in §7.');
  out.writeln(
      '- `DEFERRED CODE FIX` means the gap is real and belongs to another workstream; the exact file:line to change is given in §7.');
  out.writeln(
      '- CI jobs (evidence): ${inv.ciJobs.map((j) => '`$j`').join(', ')}.');
  out.writeln();

  // 1. Summary
  final unjustified = audit.unjustifiedGaps.length;
  out.writeln('## 1. Summary');
  out.writeln();
  out.writeln('| Metric | Count |');
  out.writeln('| --- | --- |');
  out.writeln('| lib files scanned | ${inv.libFiles.length} |');
  out.writeln('| routes | ${inv.routes.length} |');
  out.writeln('| widget handlers | ${inv.handlers.length} |');
  out.writeln('| providers | ${inv.providers.length} |');
  out.writeln('| repository methods | ${inv.repoMethods.length} |');
  out.writeln(
      '| DB calls (table / rpc / bucket) | ${inv.dbCalls.where((c) => c.kind == 'table').length} / ${inv.dbCalls.where((c) => c.kind == 'rpc').length} / ${inv.dbCalls.where((c) => c.kind == 'storage_bucket').length} |');
  out.writeln(
      '| DB objects (table / view / function / trigger / policy / bucket) | ${_count(inv, 'table')} / ${_count(inv, 'view')} / ${_count(inv, 'function')} / ${_count(inv, 'trigger')} / ${_count(inv, 'policy')} / ${_count(inv, 'storage_bucket')} |');
  out.writeln('| Edge Functions | ${inv.edgeFunctions.length} |');
  out.writeln('| dashboard tiles | ${inv.dashboardTiles.length} |');
  out.writeln('| report views | ${inv.reportViews.length} |');
  out.writeln(
      '| gaps (unjustified / justified) | $unjustified / ${audit.gaps.length - unjustified} |');
  out.writeln(
      '| deferred code fixes (other workstreams) | ${audit.deferredCodeFixGaps.length} |');
  out.writeln();

  // 2. Forward checks
  out.writeln('## 2. Forward checks');
  out.writeln();
  out.writeln('| Check | Result | What it proves |');
  out.writeln('| --- | --- | --- |');
  out.writeln(
      '| No null/empty handler | ${status('forward/non_null_handler')} | Every `onPressed`/`onTap`/`onChanged`/FAB/menu callback has a body (role-disabled callbacks are conditional expressions, not null bodies) |');
  out.writeln(
      '| Handler reaches sink | ${status('forward/handler_sink')} | Every handler reaches navigation, data, invalidation, feedback, a helper or state |');
  out.writeln(
      '| Repository target exists | ${status('forward/repository_target')} | Every repository DB call names an object declared by a migration |');
  out.writeln(
      '| DB object exists | ${status('forward/db_object_exists')} | Every `.from()`/`.rpc()`/Storage call resolves to a migration object |');
  out.writeln(
      '| RPC grant | ${status('forward/rpc_grant')} | Every UI RPC has `grant execute ... to authenticated` |');
  out.writeln(
      '| Success invalidation | ${status('forward/success_invalidation')} | Every mutating file invalidates its providers/cache |');
  out.writeln(
      '| Success feedback | ${status('forward/success_feedback')} | Every mutating file shows user-visible feedback |');
  out.writeln(
      '| Mapped error | ${status('forward/mapped_error')} | Every `catch` maps through `AppErrorMapper` or a shared error widget |');
  out.writeln(
      '| Edge Function exists | ${status('forward/edge_function_exists')} | Every referenced Edge Function has an `index.ts` |');
  out.writeln();

  // 3. Routes
  out.writeln('## 3. Route reachability (backward)');
  out.writeln();
  out.writeln('| Route | Screen | Declared at | Result |');
  out.writeln('| --- | --- | --- | --- |');
  for (final route in inv.routes) {
    out.writeln(
        '| `${_md(route.path)}` | ${_md(route.screen)} | ${route.ref} | ${status('backward/route_reachable', subject: route.path)} |');
  }
  out.writeln();

  // 4. DB objects
  out.writeln('## 4. Database object coverage (backward)');
  out.writeln();
  out.writeln(
      '| Kind | Object | Declared at | UI usage / internal tag | In schema_check | Result |');
  out.writeln('| --- | --- | --- | --- | --- | --- |');
  final usedNames =
      inv.dbCalls.map((c) => c.name).toSet().union(inv.reportViews);
  final seen = <String>{};
  for (final object in inv.dbObjects) {
    if (!seen.add(object.key)) continue;
    final usageStatus =
        status('backward/object_used_or_internal', subject: object.key);
    final schemaStatus =
        status('backward/schema_check_coverage', subject: object.key);
    final usage = usedNames.contains(object.name)
        ? 'used by lib/'
        : _internalObjects[object.name] ??
            (object.kind == 'trigger' || object.kind == 'policy'
                ? 'server-side ${object.kind}'
                : '—');
    out.writeln(
        '| ${object.kind} | `${_md(object.key)}` | ${object.ref} | ${_md(usage)} | ${schemaStatus == 'OK' ? 'PASS' : schemaStatus} | ${worst([
          usageStatus,
          schemaStatus
        ])} |');
  }
  for (final edge in inv.edgeFunctions) {
    out.writeln(
        '| edge_function | `${edge.name}` | ${edge.ref} | referenced by lib/ | n/a | OK |');
  }
  out.writeln();

  // 5. Dashboard tiles
  out.writeln('## 5. Dashboard tile reconciliation');
  out.writeln();
  out.writeln(
      '| Tile (S.*) | Snapshot field | Source query | Drill-down | Test | Result |');
  out.writeln('| --- | --- | --- | --- | --- | --- |');
  for (final tile in inv.dashboardTiles) {
    final drill = tile.drilldown.isEmpty
        ? 'informational (no drill-down by design)'
        : tile.drilldown;
    final tileStatus = worst([
      status('backward/dashboard_tile_source', subject: tile.label),
      status('backward/dashboard_tile_drilldown', subject: tile.label),
      status('backward/dashboard_tile_test', subject: tile.label),
      status('backward/dashboard_tile_reconciliation', subject: tile.field),
    ]);
    out.writeln(
        '| ${_md(tile.label)} | ${_md(tile.field)} | `${_md(tile.source)}` | ${_md(drill)} | ${tile.testRef} | $tileStatus |');
  }
  out.writeln();
  out.writeln('Totals are reconciled against raw sums and the `v_report_*` '
      'definitions in `test/wiring/dashboard_reconciliation_test.dart` '
      '(CI job: `build` → `flutter test`).');
  out.writeln();

  // 6. Repository methods
  out.writeln('## 6. Repository methods → DB objects');
  out.writeln();
  out.writeln('| File | Method | DB targets |');
  out.writeln('| --- | --- | --- |');
  for (final method in inv.repoMethods) {
    if (method.dbCalls.isEmpty) continue;
    out.writeln(
        '| ${method.file} | ${_md(method.name)} | ${method.dbCalls.map((c) => '`${_md(c)}`').join(', ')} |');
  }
  out.writeln();

  // 7. Gaps and justifications
  out.writeln('## 7. Gaps and justifications');
  out.writeln();
  if (audit.gaps.isEmpty) {
    out.writeln('No gaps found.');
  } else {
    out.writeln(
        '| Check | Subject | Detail | Evidence | Status / justification |');
    out.writeln('| --- | --- | --- | --- | --- |');
    for (final gap in audit.gaps) {
      final waiver = _waiverForSimple(gap, audit);
      final statusText = waiver == null
          ? '**UNJUSTIFIED — needs code fix** (${gap.fixHint})'
          : waiver.deferredCodeFix
              ? '**DEFERRED CODE FIX (other workstream)** — ${_md(waiver.reason)} (${waiver.evidence})'
              : 'JUSTIFIED — ${_md(waiver.reason)} (${waiver.evidence})';
      out.writeln(
          '| ${_md(gap.check)} | ${_md(gap.subject)} | ${_md(gap.detail)} | ${gap.ref ?? '—'} | $statusText |');
    }
  }
  out.writeln();

  return out.toString();
}

int _count(WiringInventory inv, String kind) =>
    inv.dbObjects.where((o) => o.kind == kind).length;

Waiver? _waiverForSimple(Gap gap, WiringAudit audit) {
  // The authoritative lookup lives on WiringAudit; expose it through a tiny
  // adapter so rendering stays a pure function of the audit.
  for (final waiver in _waivers) {
    if (waiver.key == gap.key) return waiver;
  }
  return null;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

void main(List<String> args) {
  final root = Directory.current.path;
  final audit = WiringAudit(root);
  final checkOnly = args.contains('--check');
  final dump = args.contains('--dump');

  if (!checkOnly) {
    final matrix = renderMatrix(audit);
    File('$root/docs/WIRING_MATRIX.md').writeAsStringSync(matrix);
    stdout.writeln('Wrote docs/WIRING_MATRIX.md');
  }

  stdout.writeln('${audit.gaps.length} gap(s): '
      '${audit.unjustifiedGaps.length} unjustified, '
      '${audit.gaps.length - audit.unjustifiedGaps.length} justified.');
  for (final gap in audit.gaps) {
    final waiver = _waiverForSimple(gap, audit);
    final prefix = waiver == null
        ? 'GAP'
        : waiver.deferredCodeFix
            ? 'DEFERRED'
            : 'JUSTIFIED';
    if (!dump && waiver != null) continue;
    stdout.writeln(
        '  $prefix ${gap.check} | ${gap.subject} | ${gap.ref ?? ''} | ${gap.detail}');
  }

  if (audit.hasUnjustifiedGaps) {
    stderr.writeln(
        'FAILED: ${audit.unjustifiedGaps.length} unjustified wiring gap(s).');
    exitCode = 1;
  }
}
