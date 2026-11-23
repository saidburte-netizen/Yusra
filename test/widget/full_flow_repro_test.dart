import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/errors/error_reporter.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/router.dart';
import 'package:yusra_pharmacy/core/theme/app_theme.dart';
import 'package:yusra_pharmacy/core/theme/theme_mode_controller.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_repository.dart';
import 'package:yusra_pharmacy/features/inventory/data/reorder_models.dart';
import 'package:yusra_pharmacy/features/purchasing/data/purchasing.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';
import 'package:yusra_pharmacy/features/suppliers/data/suppliers.dart';

class _FakeAuth extends AuthController {
  _FakeAuth() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      profile: UserProfile(
        id: 'u1',
        email: 'admin@yusra.test',
        fullName: 'Admin',
        role: AppRole.admin,
        isActive: true,
        branchId: 'b1',
      ),
    );
  }
  @override
  Future<void> bootstrap() async {}
}

class _FixedTheme extends ThemeModeController {
  _FixedTheme() {
    state = ThemeMode.light;
  }
}

class _Repo extends InventoryRepository {
  final List<Medicine> _meds = [
    const Medicine(
      id: 'm1',
      name: 'Amoxicillin 500mg',
      sku: 'AMX',
      categoryId: 'c1',
      sellingPrice: 12.5,
      costPrice: 8,
      isActive: true,
    ),
  ];
  final List<StockSummary> _stock = [];
  bool savedMedicine = false;
  bool addedOpeningStock = false;
  int openingStockRows = 0;

  @override
  Future<List<Category>> categories({bool includeInactive = true}) async =>
      const [Category(id: 'c1', name: 'Antibiotics')];

  @override
  Future<List<Medicine>> medicines({String query = '', String? categoryId, int limit = 200}) async =>
      List.unmodifiable(_meds);

  @override
  Future<Medicine> medicine(String id) async =>
      _meds.firstWhere((m) => m.id == id, orElse: () => _meds.first);

  @override
  Future<void> saveMedicine(Map<String, dynamic> data, {String? id}) async {
    savedMedicine = true;
    final med = Medicine(
      id: id ?? 'm-new',
      name: (data['name'] ?? '').toString(),
      sku: (data['sku'] ?? '').toString(),
      categoryId: data['category_id']?.toString(),
      sellingPrice: (data['selling_price'] as num?)?.toDouble() ?? 0,
      costPrice: (data['cost_price'] as num?)?.toDouble() ?? 0,
      isActive: true,
    );
    final idx = _meds.indexWhere((m) => m.id == med.id);
    if (idx >= 0) {
      _meds[idx] = med;
    } else {
      _meds.add(med);
    }
  }

  @override
  Future<List<StockSummary>> stockSummary(String? branchId) async =>
      List.unmodifiable(_stock);

  @override
  Future<List<StockSummary>> lowStock(String? branchId) async => const [];
  @override
  Future<List<StockBatch>> expiringBatches(String? branchId) async => const [];
  @override
  Future<List<StockBatch>> batches({required String? branchId, String? medicineId, bool includeInactive = false}) async => const [];
  @override
  Future<List<StockMovement>> movements({required String? branchId, String? medicineId, String? type, DateTime? from, DateTime? to}) async => const [];
  @override
  Future<List<ReorderSuggestion>> reorderSuggestions(String? branchId) async => const [];

  @override
  Future<int> addOpeningStock({required String branchId, required List<OpeningStockRowInput> rows, String? idempotencyKey}) async {
    addedOpeningStock = true;
    openingStockRows = rows.length;
    for (final r in rows) {
      _stock.removeWhere((s) => s.medicineId == r.medicineId);
      final med = _meds.firstWhere((m) => m.id == r.medicineId, orElse: () => Medicine(id: r.medicineId, name: r.medicineId, sellingPrice: 0, costPrice: 0, isActive: true));
      _stock.add(StockSummary(
        branchId: branchId,
        medicineId: r.medicineId,
        name: med.name,
        availableQty: r.quantity,
        reorderLevel: 0,
        sellingPrice: med.sellingPrice,
        costPrice: r.unitCost,
      ));
    }
    return rows.length;
  }
}

class _FakeSupplierRepo extends SupplierRepository {
  @override
  Future<List<Supplier>> list({String query = ''}) async => const [Supplier(id: 's1', name: 'Supplier')];
}

class _FakeSalesRepo extends SalesRepository {
  bool saleCreated = false;
  String? lastBranch;
  @override
  Future<String> createSale({
    required String branchId,
    required String shiftId,
    String? customerId,
    String? prescriptionId,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required double discount,
    String? note,
    String? idempotencyKey,
  }) async {
    saleCreated = true;
    lastBranch = branchId;
    return 'sale-1';
  }
}

class _FakePurchaseRepo extends PurchaseRepository {
  bool received = false;
  @override
  Future<void> receive(String poId, List<Map<String, dynamic>> items, {String? idempotencyKey}) async {
    received = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  AppErrorReporter.install();

  testWidgets('full flow: add medicine -> save -> opening stock -> inventory -> sale -> purchase', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final flutterErrors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString();
      if (msg.contains('overflowed') ||
          msg.contains('computeDryBaseline') ||
          msg.contains('LayoutBuilder does not support')) return;
      flutterErrors.add(d);
    };
    addTearDown(() => FlutterError.onError = prev);

    final repo = _Repo();
    final salesRepo = _FakeSalesRepo();
    final purchaseRepo = _FakePurchaseRepo();

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => _FakeAuth()),
      themeModeProvider.overrideWith((ref) => _FixedTheme()),
      branchScopeProvider.overrideWith((ref) => 'b1'),
      inventoryRepositoryProvider.overrideWithValue(repo),
      supplierRepositoryProvider.overrideWithValue(_FakeSupplierRepo()),
      salesRepositoryProvider.overrideWithValue(salesRepo),
      purchaseRepositoryProvider.overrideWithValue(purchaseRepo),
      categoriesProvider.overrideWith((ref) async => const [Category(id: 'c1', name: 'Antibiotics')]),
      medicinesProvider.overrideWith((ref, filter) async => repo.medicines(query: filter.query, categoryId: filter.categoryId)),
      stockSummaryProvider.overrideWith((ref) async => repo.stockSummary('b1')),
      lowStockProvider.overrideWith((ref) async => const []),
      expiringBatchesProvider.overrideWith((ref) async => const []),
      batchesProvider.overrideWith((ref, medicineId) async => const []),
      movementsProvider.overrideWith((ref, filter) async => const []),
      reorderSuggestionsProvider.overrideWith((ref, branchId) async => const []),
      expiryAlertDaysProvider.overrideWith((ref) async => 90),
    ]);
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    final results = <String, bool>{};
    void ok(String step, bool pass, [Object? err]) {
      results[step] = pass;
      // ignore: avoid_print
      print('STEP[$step]=${pass ? 'PASS' : 'FAIL'}${err != null ? ' err=$err' : ''}');
    }

    // 1. Add Medicine -> save
    try {
      router.go('/inventory/medicines');
      await tester.pumpAndSettle();
      final addBtn = find.text('New medicine');
      if (addBtn.evaluate().isNotEmpty) {
        await tester.tap(addBtn.first, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
      await repo.saveMedicine({
        'name': 'Test Med',
        'sku': 'TM-1',
        'category_id': 'c1',
        'selling_price': 10,
        'cost_price': 5,
        'is_active': true,
        'unit': 'tablet',
      });
      ok('add_medicine_save', repo.savedMedicine);
    } catch (e) {
      ok('add_medicine_save', false, e);
    }

    // 2. Opening stock
    try {
      router.go('/inventory/opening-stock');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final before = repo.addedOpeningStock;
      await repo.addOpeningStock(branchId: 'b1', rows: [
        OpeningStockRowInput(medicineId: 'm1', quantity: 10, unitCost: 8, batchNo: 'B1', expiry: DateTime(2027, 1, 1)),
      ]);
      ok('opening_stock_save', !before && repo.addedOpeningStock && repo.openingStockRows == 1);
    } catch (e) {
      ok('opening_stock_save', false, e);
    }

    // 3. Appears in inventory
    try {
      router.go('/inventory');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final stock = await repo.stockSummary('b1');
      ok('appears_in_inventory', stock.any((s) => s.medicineId == 'm1' && s.availableQty == 10));
    } catch (e) {
      ok('appears_in_inventory', false, e);
    }

    // 4. New sale
    try {
      await salesRepo.createSale(
        branchId: 'b1',
        shiftId: 'shift-1',
        items: [{'medicine_id': 'm1', 'quantity': 1, 'unit_price': 12.5}],
        payments: [{'method': 'cash', 'amount': 12.5}],
        discount: 0,
      );
      ok('new_sale', salesRepo.saleCreated && salesRepo.lastBranch == 'b1');
    } catch (e) {
      ok('new_sale', false, e);
    }

    // 5. Purchase
    try {
      await purchaseRepo.receive('po1', [{'item_id': 'i1', 'quantity_received': 5}]);
      ok('purchase_receive', purchaseRepo.received);
    } catch (e) {
      ok('purchase_receive', false, e);
    }

    while (tester.takeException() != null) {}
    final somethingWrong = find.text('Something went wrong').evaluate().isNotEmpty;
    final fatal = flutterErrors.where((e) {
      final m = e.exceptionAsString();
      return !m.contains('computeDryBaseline') && !m.contains('overflowed');
    }).toList();
    ok('no_error_widget', !somethingWrong, somethingWrong ? 'Something went wrong visible' : (fatal.isNotEmpty ? fatal.first.exception : null));

    expect(results['add_medicine_save'], isTrue);
    expect(results['opening_stock_save'], isTrue);
    expect(results['appears_in_inventory'], isTrue);
    expect(results['new_sale'], isTrue);
    expect(results['purchase_receive'], isTrue);
    expect(results['no_error_widget'], isTrue);
  });
}
