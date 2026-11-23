import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/errors/app_error.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/strings.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_screen.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

List<FlutterErrorDetails> _captureErrors() {
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
            id: 'user-1',
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

DashboardSnapshot _dummySnapshot() => DashboardSnapshot(
      todaySales: 1250,
      monthSales: 18400,
      grossProfitToday: 320,
      invoiceCount: 7,
      openShifts: 2,
      lowStock: 3,
      expiringSoon: 1,
      expired: 0,
      pendingPrescriptions: 1,
      pendingOrders: 2,
      topMedicines: [
        {'name': 'Paracetamol', 'qty': 12},
      ],
      failedSections: const [
        'Sales detail (Error code: PGRST200)',
        'Activity log (Error code: 42P01)',
      ],
    );

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required DashboardSnapshot? snapshot,
  String? error,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        home: DashboardScreen(initialSnapshot: snapshot, initialError: error),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  for (final viewport in sizes) {
    testWidgets('Dashboard partial-data banner lists codes at ${viewport.name}',
        (tester) async {
      _setSize(tester, viewport.size);
      final errors = _captureErrors();

      await _pumpDashboard(tester, snapshot: _dummySnapshot());

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.textContaining('Some sections could not be loaded'),
          findsOneWidget);
      expect(find.textContaining('Sales detail (Error code: PGRST200)'),
          findsOneWidget);
      expect(find.textContaining('Activity log (Error code: 42P01)'),
          findsOneWidget);
      expect(find.text(S.somethingWrong), findsNothing);
    });

    testWidgets(
        'Dashboard top-level error never shows a bare generic message'
        ' at ${viewport.name}', (tester) async {
      _setSize(tester, viewport.size);
      final errors = _captureErrors();
      final mapped = AppErrorMapper.from(
        const PostgrestException(
          message: 'permission denied for table sales',
          code: '42501',
        ),
      );

      await _pumpDashboard(tester, snapshot: null, error: mapped.message);

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.textContaining('Error code: 42501'), findsOneWidget);
      expect(find.textContaining('permission'), findsOneWidget);
      expect(find.text(S.somethingWrong), findsNothing);
    });
  }
}
