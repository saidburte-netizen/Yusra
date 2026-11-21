import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/pos/screens/payment_dialog.dart';
import 'package:yusra_pharmacy/features/prescriptions/data/prescriptions.dart';
import 'package:yusra_pharmacy/features/prescriptions/screens/prescriptions_screen.dart';
import 'package:yusra_pharmacy/features/purchasing/data/purchasing.dart';
import 'package:yusra_pharmacy/features/purchasing/screens/purchase_order_screen.dart';
import 'package:yusra_pharmacy/features/purchasing/screens/purchase_orders_screen.dart';
import 'package:yusra_pharmacy/features/reports/reports_screen.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';
import 'package:yusra_pharmacy/features/shifts/screens/shifts_screen.dart';
import 'package:yusra_pharmacy/features/suppliers/data/suppliers.dart';

import 'layout_core_test.dart' as core;

class _FakePurchaseRepository extends PurchaseRepository {
  @override
  Future<PurchaseOrder> order(String id) async => _order;

  @override
  Future<List<PurchaseOrderItem>> items(String poId) async => [
        const PurchaseOrderItem(
          id: 'item-1',
          poId: 'po-1',
          medicineId: 'med-1',
          quantityOrdered: 10,
          quantityReceived: 2,
          unitCost: 8,
          medicineName: 'Amoxicillin 500mg',
        ),
      ];
}

const _order = PurchaseOrder(
  id: 'po-1',
  poNo: 'PO-001',
  branchId: 'branch-1',
  supplierId: 'supplier-1',
  supplierName: 'Ethio Pharma',
  status: 'partially_received',
  total: 80,
);

const _prescription = Prescription(
  id: 'rx-1',
  rxNo: 'RX-001',
  branchId: 'branch-1',
  patientName: 'Marta Tesfa',
  prescriberName: 'Dr. Kebede',
  status: 'pending',
);

final _shift = Shift(
  id: 'shift-1',
  branchId: 'branch-1',
  cashierId: 'user-1',
  openedAt: DateTime(2026, 11, 20, 8),
  closedAt: DateTime(2026, 11, 20, 16),
  openingCash: 100,
  closingCash: 325,
  expectedCash: 325,
  difference: 0,
  status: 'closed',
  cashierName: 'Asmara Tesfa',
);

List<Override> _overrides(AppRole role) => [
      ...core.authOverrides(role),
      branchScopeProvider.overrideWith((ref) => 'branch-1'),
      purchaseRepositoryProvider.overrideWithValue(_FakePurchaseRepository()),
      purchaseOrdersProvider.overrideWith((ref) async => [_order]),
      purchaseOrderProvider.overrideWith((ref, id) async => _order),
      purchaseItemsProvider.overrideWith((ref, id) async => [
            const PurchaseOrderItem(
              id: 'item-1',
              poId: 'po-1',
              medicineId: 'med-1',
              quantityOrdered: 10,
              quantityReceived: 2,
              unitCost: 8,
              medicineName: 'Amoxicillin 500mg',
            ),
          ]),
      suppliersProvider.overrideWith((ref, query) async => [
            const Supplier(id: 'supplier-1', name: 'Ethio Pharma'),
          ]),
      prescriptionsProvider.overrideWith((ref, status) async => [
            _prescription,
          ]),
      myOpenShiftProvider.overrideWith((ref) async => null),
      shiftsProvider.overrideWith((ref, openOnly) async => [_shift]),
      receiptSettingsProvider.overrideWith((ref) async => const ReceiptSettings(
            pharmacyName: 'Yusra Pharmacy',
            tagline: 'Care made easy',
            address: '',
            phone: '',
            tin: '',
            licenseNo: '',
            footer: 'Thank you.',
            vatRate: 0.15,
            maxCashierDiscountPct: 5,
          )),
      reportRowsProvider
          .overrideWithValue((report, branchId, from, to) async => [
                {
                  'date': '2026-11-20',
                  'invoices': 12,
                  'gross': 1250.0,
                  'discounts': 25.0,
                  'vat': 150.0,
                  'net': 1225.0,
                },
              ]),
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
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  final screens = <({String name, Widget Function() build, AppRole role})>[
    (
      name: 'purchase orders',
      build: () => const PurchaseOrdersScreen(),
      role: AppRole.admin,
    ),
    (
      name: 'purchase order draft',
      build: () => const PurchaseOrderScreen(orderId: 'new'),
      role: AppRole.admin,
    ),
    (
      name: 'purchase order receiving',
      build: () => const PurchaseOrderScreen(orderId: 'po-1'),
      role: AppRole.admin,
    ),
    (
      name: 'purchase order read only',
      build: () => const PurchaseOrderScreen(orderId: 'po-1'),
      role: AppRole.pharmacist,
    ),
    (
      name: 'reports',
      build: () => const ReportsScreen(),
      role: AppRole.admin,
    ),
    (
      name: 'prescriptions',
      build: () => const PrescriptionsScreen(),
      role: AppRole.pharmacist,
    ),
    (
      name: 'shifts',
      build: () => const ShiftsScreen(),
      role: AppRole.admin,
    ),
  ];

  for (final viewport in sizes) {
    for (final screen in screens) {
      testWidgets('${screen.name} has no overflow at ${viewport.name}',
          (tester) async {
        core.setTestSize(tester, viewport.size);
        final errors = core.captureFlutterErrors();

        await _pump(tester, screen.build(), screen.role);

        expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      });
    }

    testWidgets(
        'purchase order permissions follow the matrix at '
        '${viewport.name}', (tester) async {
      core.setTestSize(tester, viewport.size);
      final errors = core.captureFlutterErrors();

      await _pump(
        tester,
        const PurchaseOrderScreen(orderId: 'po-1'),
        AppRole.pharmacist,
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Approve & send'), findsNothing);
      expect(find.text('Receive goods'), findsNothing);
      expect(find.text('Ethio Pharma'), findsOneWidget);

      // Force a fresh State so the role change is observed by initState.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        const PurchaseOrderScreen(orderId: 'po-1'),
        AppRole.admin,
      );
      expect(find.text('Receive goods'), findsOneWidget);
    });

    testWidgets('payment dialog fits ${viewport.name}', (tester) async {
      core.setTestSize(tester, viewport.size);
      final errors = core.captureFlutterErrors();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPaymentDialog(context, total: 25),
              child: const Text('open payment'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open payment'));
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.textContaining('Payment'), findsWidgets);
      expect(find.text('Confirm ETB 25.00'), findsOneWidget);
    });
  }
}
