import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_repository.dart';
import 'package:yusra_pharmacy/features/inventory/screens/adjustments_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/alerts_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/batches_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/categories_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/medicine_detail_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/medicines_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/movements_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/stock_overview_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/stocktake_screen.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';
import 'package:yusra_pharmacy/features/sales/screens/returns_screen.dart';
import 'package:yusra_pharmacy/features/sales/screens/sale_detail_screen.dart';
import 'package:yusra_pharmacy/features/sales/screens/sales_screen.dart';

import 'layout_core_test.dart' as core;

class _FakeInventoryRepository extends InventoryRepository {
  @override
  Future<List<Category>> categories({bool includeInactive = true}) async => [
        const Category(id: 'cat-1', name: 'Antibiotics'),
      ];

  @override
  Future<List<Medicine>> medicines({
    String query = '',
    String? categoryId,
  }) async =>
      [
        const Medicine(
          id: 'med-1',
          name: 'Amoxicillin 500mg',
          sku: 'AMX-500',
          categoryId: 'cat-1',
          sellingPrice: 12.5,
          costPrice: 8,
          isActive: true,
        ),
      ];

  @override
  Future<List<StockBatch>> batches({
    required String? branchId,
    String? medicineId,
    bool includeInactive = false,
  }) async =>
      [
        StockBatch(
          id: 'batch-1',
          branchId: 'branch-1',
          medicineId: 'med-1',
          batchNo: 'B-001',
          expiryDate: DateTime(2030),
          quantity: 20,
          medicineName: 'Amoxicillin 500mg',
        ),
      ];

  @override
  Future<List<StockMovement>> movements({
    required String? branchId,
    String? medicineId,
    String? type,
    DateTime? from,
    DateTime? to,
  }) async =>
      const [];
}

const _medicine = Medicine(
  id: 'med-1',
  name: 'Amoxicillin 500mg',
  sku: 'AMX-500',
  categoryId: 'cat-1',
  sellingPrice: 12.5,
  costPrice: 8,
);

final _batch = StockBatch(
  id: 'batch-1',
  branchId: 'branch-1',
  medicineId: 'med-1',
  batchNo: 'B-001',
  expiryDate: DateTime(2030),
  quantity: 20,
  medicineName: 'Amoxicillin 500mg',
);

final _movement = StockMovement(
  id: 1,
  branchId: 'branch-1',
  medicineId: 'med-1',
  type: 'adjustment',
  quantityChange: -2,
  medicineName: 'Amoxicillin 500mg',
  reason: 'Count correction',
  createdAt: DateTime(2026, 11, 20),
);

final _saleReturn = SaleReturn(
  id: 'return-1',
  returnNo: 'RET-001',
  saleId: 'sale-1',
  branchId: 'branch-1',
  reason: 'Wrong item',
  refundAmount: 12.5,
  createdAt: DateTime(2026, 11, 21),
  invoiceNo: 'INV-001',
);

final _sale = Sale(
  id: 'sale-1',
  invoiceNo: 'INV-001',
  branchId: 'branch-1',
  cashierId: 'user-1',
  total: 25,
  paid: 25,
  cashierName: 'Asmara Tesfa',
  createdAt: DateTime(2026, 11, 20),
);

List<Override> _overrides(AppRole role) => [
      ...core.authOverrides(role),
      branchScopeProvider.overrideWith((ref) => 'branch-1'),
      inventoryRepositoryProvider.overrideWithValue(_FakeInventoryRepository()),
      categoriesProvider.overrideWith((ref) async => [
            const Category(id: 'cat-1', name: 'Antibiotics'),
          ]),
      medicinesProvider.overrideWith((ref, filter) async => [_medicine]),
      stockSummaryProvider.overrideWith((ref) async => [
            const StockSummary(
              branchId: 'branch-1',
              medicineId: 'med-1',
              name: 'Amoxicillin 500mg',
              availableQty: 20,
            ),
          ]),
      lowStockProvider.overrideWith((ref) async => [
            const StockSummary(
              branchId: 'branch-1',
              medicineId: 'med-1',
              name: 'Amoxicillin 500mg',
              availableQty: 5,
              reorderLevel: 10,
            ),
          ]),
      expiringBatchesProvider.overrideWith((ref) async => [_batch]),
      batchesProvider.overrideWith((ref, medicineId) async => [_batch]),
      movementsProvider.overrideWith((ref, filter) async => [_movement]),
      expiryAlertDaysProvider.overrideWith((ref) async => 90),
      salesProvider.overrideWith((ref, filter) async => [_sale]),
      cashiersProvider.overrideWith((ref) async => [
            {
              'id': 'user-1',
              'full_name': 'Asmara Tesfa',
            },
          ]),
      saleProvider.overrideWith((ref, id) async => _sale),
      saleItemsProvider.overrideWith((ref, id) async => [
            const SaleItem(
              id: 'item-1',
              saleId: 'sale-1',
              medicineId: 'med-1',
              medicineName: 'Amoxicillin 500mg',
              quantity: 2,
              unitPrice: 12.5,
              lineTotal: 25,
            ),
          ]),
      salePaymentsProvider.overrideWith((ref, id) async => [
            const SalePayment(
              id: 'pay-1',
              saleId: 'sale-1',
              method: 'cash',
              amount: 25,
            ),
          ]),
      saleReturnsProvider.overrideWith((ref) async => [_saleReturn]),
    ];

Future<void> _pump(WidgetTester tester, Widget screen, AppRole role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(role),
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  final screens = <({String name, Widget Function() build})>[
    (name: 'medicines', build: () => const MedicinesScreen()),
    (name: 'categories', build: () => const CategoriesScreen()),
    (name: 'batches', build: () => const BatchesScreen()),
    (
      name: 'medicine detail',
      build: () => const MedicineDetailScreen(medicineId: 'med-1'),
    ),
    (name: 'stocktake', build: () => const StocktakeScreen()),
    (name: 'sales', build: () => const SalesScreen()),
    (
      name: 'sale detail',
      build: () => const SaleDetailScreen(id: 'sale-1'),
    ),
    (name: 'stock overview', build: () => const StockOverviewScreen()),
    (name: 'adjustments', build: () => const AdjustmentsScreen()),
    (name: 'movements', build: () => const MovementsScreen()),
    (name: 'alerts', build: () => const AlertsScreen()),
    (name: 'returns', build: () => const ReturnsScreen()),
  ];

  for (final viewport in sizes) {
    for (final screen in screens) {
      testWidgets('${screen.name} has no overflow at ${viewport.name}',
          (tester) async {
        core.setTestSize(tester, viewport.size);
        final errors = core.captureFlutterErrors();

        await _pump(tester, screen.build(), AppRole.admin);

        expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      });
    }

    testWidgets('cashier sales history is own-only at ${viewport.name}',
        (tester) async {
      core.setTestSize(tester, viewport.size);
      final errors = core.captureFlutterErrors();

      await _pump(tester, const SalesScreen(), AppRole.cashier);

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Cashier'), findsNothing);
      expect(find.text('INV-001'), findsOneWidget);
    });
  }
}
