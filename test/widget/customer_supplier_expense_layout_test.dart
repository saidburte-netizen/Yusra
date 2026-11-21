import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/customers/data/customers.dart';
import 'package:yusra_pharmacy/features/customers/screens/customers_screen.dart';
import 'package:yusra_pharmacy/features/expenses/expenses_screen.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/purchasing/data/purchasing.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';
import 'package:yusra_pharmacy/features/suppliers/data/suppliers.dart';
import 'package:yusra_pharmacy/features/suppliers/screens/suppliers_screen.dart';

void setTestSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

List<FlutterErrorDetails> captureFlutterErrors() {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

List<Override> _overrides() => [
      authProvider.overrideWith((ref) {
        final controller = AuthController();
        controller.state = const AuthState(
          status: AuthStatus.authenticated,
          profile: UserProfile(
            id: 'admin-1',
            email: 'admin@yusra.test',
            fullName: 'Admin User',
            role: AppRole.admin,
            isActive: true,
            branchId: 'branch-1',
          ),
        );
        return controller;
      }),
      branchScopeProvider.overrideWith((ref) => 'branch-1'),
    ];

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

Customer _customer() => const Customer(
      id: 'customer-1',
      name: 'Asmara Tesfa',
      phone: '+251911000001',
      email: 'asmara@example.test',
      address: 'Asmera',
      isActive: true,
    );

List<Customer> _customers() => [
      _customer(),
      const Customer(
        id: 'customer-2',
        name: 'Nahom Gebre',
        phone: '+251911000002',
        isActive: false,
      ),
    ];

Sale _sale() => Sale(
      id: 'sale-1',
      invoiceNo: 'INV-001',
      branchId: 'branch-1',
      cashierId: 'user-1',
      customerId: 'customer-1',
      total: 125.5,
      status: 'completed',
      createdAt: DateTime(2026, 11, 20, 10, 30),
    );

Supplier _supplier() => const Supplier(
      id: 'supplier-1',
      name: 'Zemen Supplies',
      contactPerson: 'Yohannes',
      phone: '+251911000003',
      email: 'sales@zemen.test',
      tin: '1234567890',
      paymentTerms: 'Net 15',
      isActive: true,
    );

List<Supplier> _suppliers() => [
      _supplier(),
      const Supplier(id: 'supplier-2', name: 'Red Sea Distributors'),
    ];

PurchaseOrder _order() => PurchaseOrder(
      id: 'po-1',
      poNo: 'PO-001',
      branchId: 'branch-1',
      supplierId: 'supplier-1',
      status: 'received',
      orderDate: DateTime(2026, 11, 18),
      expectedDate: DateTime(2026, 11, 22),
      total: 2500,
    );

List<Map<String, dynamic>> _expenses() => [
      {
        'id': 'expense-1',
        'branch_id': 'branch-1',
        'expense_date': '2026-11-20T08:00:00.000Z',
        'category': 'Rent',
        'amount': 15000,
        'payment_method': 'bank_transfer',
        'status': 'pending',
        'description': 'November rent',
      },
      {
        'id': 'expense-2',
        'branch_id': 'branch-1',
        'expense_date': '2026-11-19T08:00:00.000Z',
        'category': 'Utilities',
        'amount': 850,
        'payment_method': 'cash',
        'status': 'approved',
        'description': 'Electricity',
      },
    ];

void main() {
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  for (final viewport in sizes) {
    testWidgets('CustomersScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, CustomersScreen(initialCustomers: _customers()));
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Asmara Tesfa'), findsOneWidget);
      expect(find.text('Nahom Gebre'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('CustomerDetailScreen renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        CustomerDetailScreen(
          id: 'customer-1',
          initialCustomer: _customer(),
          initialStats: const CustomerStats(
            visits: 4,
            lifetimeSpend: 620.25,
            lastVisit: null,
          ),
          initialSales: [_sale()],
        ),
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Asmara Tesfa'), findsOneWidget);
      expect(find.text('Recent purchases'), findsOneWidget);
      expect(find.text('INV-001'), findsOneWidget);
    });

    testWidgets('SuppliersScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, SuppliersScreen(initialSuppliers: _suppliers()));
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Zemen Supplies'), findsOneWidget);
      expect(find.text('Red Sea Distributors'), findsOneWidget);
    });

    testWidgets('SupplierDetailScreen renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        SupplierDetailScreen(
          supplierId: 'supplier-1',
          initialSupplier: _supplier(),
          initialOrders: [_order()],
        ),
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Zemen Supplies'), findsOneWidget);
      expect(find.text('Purchase orders'), findsOneWidget);
      expect(find.text('PO-001'), findsOneWidget);
    });

    testWidgets('ExpensesScreen renders list and filters at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, ExpensesScreen(initialRows: _expenses()));
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('November rent'), findsOneWidget);
      expect(find.text('Electricity'), findsOneWidget);
      expect(find.byTooltip('Approve'), findsOneWidget);
      expect(find.byTooltip('Reject'), findsOneWidget);
    });

    testWidgets('ExpensesScreen error state renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        const ExpensesScreen(
            initialError: 'Error code: PGRST200 — permission denied'),
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.textContaining('PGRST200'), findsOneWidget);
    });
  }
}
