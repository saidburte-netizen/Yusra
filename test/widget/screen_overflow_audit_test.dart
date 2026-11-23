import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_screen.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_models.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/inventory/screens/stock_overview_screen.dart';
import 'package:yusra_pharmacy/features/inventory/screens/medicines_screen.dart';
import 'package:yusra_pharmacy/features/pos/screens/pos_screen.dart';
import 'package:yusra_pharmacy/features/sales/data/sales.dart';

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

List<FlutterErrorDetails> _captureOverflow() {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
    final msg = details.exceptionAsString();
    if (!msg.contains('overflowed')) previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  List<Override> overrides = const [],
}) async {
  _setSize(tester, size);
  final errors = _captureOverflow();
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => child)],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
  final overflows = errors
      .where((e) => e.exceptionAsString().contains('overflowed'))
      .toList();
  expect(overflows, isEmpty,
      reason: 'Overflow at ${size.width.toInt()}x${size.height.toInt()}:\n'
          '${overflows.map((e) => e.exceptionAsString()).join('\n')}');
}

List<Override> _baseOverrides() => [
      authProvider.overrideWith((ref) {
        final c = AuthController();
        c.state = const AuthState(
          status: AuthStatus.authenticated,
          profile: UserProfile(
            id: 'u1',
            email: 'admin@yusra.test',
            fullName: 'Admin User',
            role: AppRole.superAdmin,
            isActive: true,
            branchId: 'b1',
          ),
        );
        return c;
      }),
      branchScopeProvider.overrideWith((ref) => 'b1'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sizes = [const Size(360, 800), const Size(412, 915)];

  for (final size in sizes) {
    testWidgets(
        'Dashboard no overflow ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _pump(
        tester,
        size: size,
        overrides: _baseOverrides(),
        child: DashboardScreen(
          initialSnapshot: DashboardSnapshot(
            todaySales: 1200,
            monthSales: 5000,
            grossProfitToday: 300,
            invoiceCount: 12,
            openShifts: 1,
            lowStock: 2,
            expiringSoon: 1,
            expired: 0,
            pendingPrescriptions: 0,
            pendingOrders: 1,
          ),
          initialError: null,
        ),
      );
    });

    testWidgets(
        'Inventory/Stock overview no overflow ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _pump(
        tester,
        size: size,
        overrides: [
          ..._baseOverrides(),
          stockSummaryProvider.overrideWith((ref) async => [
                StockSummary(
                  branchId: 'b1',
                  medicineId: 'm1',
                  name: 'Paracetamol',
                  sku: 'P1',
                  unit: 'Pack',
                  availableQty: 20,
                  expiredQty: 0,
                  reorderLevel: 5,
                  nearestExpiry: DateTime(2027, 1, 1),
                  costPrice: 10,
                  sellingPrice: 15,
                ),
              ]),
          expiryAlertDaysProvider.overrideWith((ref) => Future.value(90)),
        ],
        child: const StockOverviewScreen(),
      );
    });

    testWidgets('POS no overflow ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _pump(
        tester,
        size: size,
        overrides: [
          ..._baseOverrides(),
          myOpenShiftProvider.overrideWith((ref) async => const Shift(
                id: 's1',
                branchId: 'b1',
                cashierId: 'u1',
                openedAt: null,
                openingCash: 100,
                status: 'open',
              )),
          posMedicinesProvider.overrideWith((ref) async => const [
                Medicine(
                  id: 'm1',
                  name: 'Paracetamol 500mg',
                  sku: 'PCM-500',
                  sellingPrice: 12.5,
                  isActive: true,
                ),
              ]),
          stockSummaryProvider.overrideWith((ref) async => const [
                StockSummary(
                  branchId: 'b1',
                  medicineId: 'm1',
                  name: 'Paracetamol 500mg',
                  sku: 'PCM-500',
                  unit: 'Pack',
                  availableQty: 20,
                  expiredQty: 0,
                  reorderLevel: 5,
                  nearestExpiry: null,
                  costPrice: 10,
                  sellingPrice: 12.5,
                ),
              ]),
          categoriesProvider.overrideWith((ref) async => const []),
        ],
        child: const PosScreen(),
      );
    });

    testWidgets(
        'Medicines no overflow ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await _pump(
        tester,
        size: size,
        overrides: [
          ..._baseOverrides(),
          medicinesProvider.overrideWith((ref, filter) async => const [
                Medicine(
                  id: 'm1',
                  name: 'Paracetamol',
                  sku: 'P1',
                  sellingPrice: 15,
                  isActive: true,
                ),
              ]),
          categoriesProvider.overrideWith((ref) async => const []),
        ],
        child: const MedicinesScreen(),
      );
    });
  }
}
