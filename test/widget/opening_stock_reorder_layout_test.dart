import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_repository.dart';
import 'package:yusra_pharmacy/features/inventory/data/reorder_models.dart';
import 'package:yusra_pharmacy/features/inventory/screens/needs_ordering_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/opening_stock_screen.dart';
import 'package:yusra_pharmacy/features/inventory/widgets/stock_widgets.dart';
import 'package:yusra_pharmacy/features/suppliers/data/suppliers.dart';

import 'layout_core_test.dart' as core;

const _medicine = Medicine(
  id: 'med-1',
  name: 'Amoxicillin 500mg',
  sku: 'AMX-500',
  categoryId: 'cat-1',
  sellingPrice: 12.5,
  costPrice: 8,
  reorderLevel: 10,
  targetLevel: 20,
);

class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository({List<ReorderSuggestion>? suggestions})
      : suggestions = suggestions ?? const <ReorderSuggestion>[];

  final Map<String, Medicine> _saved = <String, Medicine>{};
  final List<ReorderSuggestion> suggestions;

  List<Medicine> get catalogue => <Medicine>[_medicine, ..._saved.values];
  Map<String, Medicine> get saved => Map.unmodifiable(_saved);

  bool _matches(Medicine medicine, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return medicine.name.toLowerCase().contains(q) ||
        medicine.sku.toLowerCase().contains(q) ||
        (medicine.barcode ?? '').toLowerCase().contains(q);
  }

  @override
  Future<List<Medicine>> medicines({
    String query = '',
    String? categoryId,
    int limit = 200,
  }) async =>
      catalogue.where((item) => _matches(item, query)).take(limit).toList();

  @override
  Future<Medicine> medicine(String id) async {
    return catalogue.firstWhere(
      (item) => item.id == id,
      orElse: () => throw StateError('Medicine $id was not saved'),
    );
  }

  @override
  Future<void> saveMedicine(Map<String, dynamic> data, {String? id}) async {
    final payload = Map<String, dynamic>.from(data);
    final key = id ?? payload['id'] as String;
    _saved[key] = Medicine.fromJson(<String, dynamic>{...payload, 'id': key});
  }

  @override
  Future<String> addStock({
    required String branchId,
    required String medicineId,
    required String batchNo,
    required DateTime expiry,
    required int quantity,
    required double cost,
    String? supplierId,
    String source = 'opening',
  }) async =>
      batchNo.isEmpty ? 'OPEN-20261122-001' : batchNo;

  @override
  Future<int> addOpeningStock({
    required String branchId,
    required List<OpeningStockRowInput> rows,
  }) async =>
      rows.length;

  @override
  Future<List<ReorderSuggestion>> reorderSuggestions(String? branchId) async =>
      suggestions;

  @override
  Future<List<String>> createDraftPurchaseOrders({
    required String branchId,
    required List<Map<String, dynamic>> lines,
  }) async =>
      const <String>['po-1'];
}

class _FakeSupplierRepository extends SupplierRepository {
  @override
  Future<List<Supplier>> list({String query = ''}) async => const [
        Supplier(id: 'supplier-1', name: 'Ethio Pharma'),
      ];
}

class _AddStockHarness extends ConsumerWidget {
  const _AddStockHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showAddStockDialog(context, ref),
            child: const Text('Open add stock'),
          ),
        ),
      );
}

List<Override> _overrides(
  _FakeInventoryRepository repository, {
  AppRole role = AppRole.storeKeeper,
}) =>
    [
      ...core.authOverrides(role),
      branchScopeProvider.overrideWith((ref) => 'branch-1'),
      inventoryRepositoryProvider.overrideWithValue(repository),
      supplierRepositoryProvider.overrideWithValue(_FakeSupplierRepository()),
      categoriesProvider.overrideWith((ref) async => const [
            Category(id: 'cat-1', name: 'Antibiotics'),
          ]),
      medicinesProvider
          .overrideWith((ref, filter) async => repository.catalogue),
      stockSummaryProvider.overrideWith((ref) async => const [
            StockSummary(
              branchId: 'branch-1',
              medicineId: 'med-1',
              name: 'Amoxicillin 500mg',
              availableQty: 12,
            ),
          ]),
      reorderSuggestionsProvider.overrideWith(
        (ref, branchId) async => repository.suggestions,
      ),
    ];

/// Captures every Flutter error so tests can assert that no overflow or other
/// layout error occurred.
List<FlutterErrorDetails> _captureLayoutErrors() => core.captureFlutterErrors();

Future<void> _tapMedicinePicker(WidgetTester tester) async {
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  Widget child,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _fieldByLabel(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );

void main() {
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  for (final viewport in sizes) {
    testWidgets('Add stock dialog source fields at ${viewport.name}',
        (tester) async {
      core.setTestSize(tester, viewport.size);
      final errors = _captureLayoutErrors();

      await _pump(
        tester,
        const _AddStockHarness(),
        _overrides(_FakeInventoryRepository()),
      );
      await tester.tap(find.text('Open add stock'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Opening stock (already in store)'), findsOneWidget);
      expect(find.text('Supplier (optional)'), findsNothing);
      expect(find.text('Batch number (optional)'), findsOneWidget);
      expect(find.text('Select expiry date'), findsOneWidget);

      await tester.tap(find.text('Opening stock (already in store)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase received').last);
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Supplier (optional)'), findsOneWidget);
      expect(find.text('Batch number (optional)'), findsOneWidget);
      expect(find.text('Select expiry date'), findsOneWidget);
    });
  }

  testWidgets('Add stock dialog can create and select a new medicine',
      (tester) async {
    core.setTestSize(tester, const Size(360, 640));
    final errors = _captureLayoutErrors();
    final repository = _FakeInventoryRepository();

    await _pump(tester, const _AddStockHarness(), _overrides(repository));
    await tester.tap(find.text('Open add stock'));
    await tester.pumpAndSettle();
    await _tapMedicinePicker(tester);
    await tester.tap(find.text('+ Add new'));
    await tester.pumpAndSettle();

    expect(find.text('New medicine'), findsOneWidget);
    await tester.enterText(_fieldByLabel('Name'), 'Paediatric Amoxicillin');
    await tester.enterText(_fieldByLabel('Unit'), 'Tablet');
    await tester.enterText(_fieldByLabel('Selling price'), '15.50');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    expect(
      repository.saved.values.single.name,
      'Paediatric Amoxicillin',
    );
    expect(
      find.textContaining('Paediatric Amoxicillin'),
      findsWidgets,
      reason: 'the new medicine must be selected in the Add stock dialog',
    );
    expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
  });

  testWidgets('Opening stock screen row editors at 360x640', (tester) async {
    core.setTestSize(tester, const Size(360, 640));
    final errors = _captureLayoutErrors();

    await _pump(
      tester,
      const OpeningStockScreen(),
      _overrides(_FakeInventoryRepository()),
    );

    expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
    expect(find.text('Opening stock'), findsOneWidget);
    expect(find.text('Add row'), findsOneWidget);
    expect(find.text('Remove row'), findsOneWidget);
    expect(find.text('Save all'), findsOneWidget);
    expect(find.text('Download template'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Row 2'), findsNothing);

    await tester.ensureVisible(find.text('Add row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    expect(find.text('Row 2'), findsOneWidget);
    expect(find.text('Remove row'), findsNWidgets(2));

    await tester.tap(find.text('Remove row').last);
    await tester.pumpAndSettle();
    expect(find.text('Row 2'), findsNothing);
    expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
  });

  testWidgets('Needs ordering screen supplier assignment at 360x640',
      (tester) async {
    core.setTestSize(tester, const Size(360, 640));
    final errors = _captureLayoutErrors();
    const suggestion = ReorderSuggestion(
      branchId: 'branch-1',
      medicineId: 'med-1',
      name: 'Amoxicillin 500mg',
      sku: 'AMX-500',
      unit: 'Pack',
      onHand: 7,
      availableQty: 7,
      expiringQty: 0,
      reorderLevel: 10,
      targetLevel: 20,
      suggestedOrderQty: 13,
      lastPurchaseCost: 8,
      reason: 'Below reorder level',
    );

    await _pump(
      tester,
      const NeedsOrderingScreen(),
      _overrides(
        _FakeInventoryRepository(suggestions: [suggestion]),
        role: AppRole.admin,
      ),
    );

    expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
    expect(find.text('Needs ordering'), findsOneWidget);
    expect(find.textContaining('Amoxicillin 500mg'), findsWidgets);
    const bannerHint =
        'Assign a supplier to every selected row below before creating '
        'purchase orders.';
    expect(find.text(bannerHint), findsOneWidget);
    expect(find.text('Choose supplier'), findsNWidgets(3));
    expect(find.text('Create purchase order(s)'), findsOneWidget);
    expect(find.text('Export / share CSV'), findsOneWidget);
    expect(find.text('Export / share PDF'), findsOneWidget);
    expect(_fieldByLabel('Order quantity'), findsOneWidget);
    final quantity = tester.widget<TextFormField>(
      _fieldByLabel('Order quantity'),
    );
    expect(quantity.enabled, isTrue);
    expect(quantity.controller?.text, '13');

    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<String?>).first);
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethio Pharma').last);
    await tester.pumpAndSettle();

    expect(find.text(bannerHint), findsNothing);
    expect(find.text('Choose supplier'), findsNothing);
    expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
  });
}
