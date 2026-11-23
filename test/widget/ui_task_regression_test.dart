import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/nav/app_shell.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/features/inventory/data/inventory_providers.dart';
import 'package:yusra_pharmacy/features/auth/change_password_screen.dart';
import 'package:yusra_pharmacy/features/dashboard/dashboard_screen.dart';
import 'package:yusra_pharmacy/features/expenses/expenses_screen.dart';

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
    if (!details.exceptionAsString().contains('overflowed')) {
      previous?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

List<Override> _authOverrides({AppRole role = AppRole.superAdmin}) => [
      authProvider.overrideWith((ref) {
        final c = AuthController();
        c.state = AuthState(
          status: AuthStatus.authenticated,
          profile: UserProfile(
            id: 'u1',
            email: 'admin@yusra.test',
            fullName: 'Admin User',
            role: role,
            isActive: true,
            branchId: 'b1',
          ),
        );
        return c;
      }),
      branchScopeProvider.overrideWith((ref) => 'b1'),
    ];

Widget _page(String label) => Scaffold(body: Center(child: Text(label)));

void main() {
  for (final size in const [Size(360, 800), Size(412, 915)]) {
    testWidgets(
        'drawer opens and navigates without error card ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      _setSize(tester, size);
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
              GoRoute(
                  path: '/dashboard',
                  builder: (_, __) => _page('Dashboard page')),
              GoRoute(
                  path: '/dashboard/pharmacy-value',
                  builder: (_, __) => _page('Pharmacy value page')),
              GoRoute(
                  path: '/dashboard/expected-expenses',
                  builder: (_, __) => _page('Expected expenses page')),
              GoRoute(path: '/pos', builder: (_, __) => _page('POS page')),
              GoRoute(
                  path: '/inventory',
                  builder: (_, __) => _page('Inventory page')),
              GoRoute(
                  path: '/purchasing/orders',
                  builder: (_, __) => _page('Purchasing page')),
              GoRoute(
                  path: '/expenses',
                  builder: (_, __) => _page('Expenses page')),
              GoRoute(
                  path: '/admin/users',
                  builder: (_, __) => _page('Users page')),
              GoRoute(
                  path: '/profile',
                  builder: (_, __) => _page('Profile page'),
                  routes: [
                    GoRoute(
                        path: 'change-password',
                        builder: (_, __) => _page('Change password page'))
                  ]),
              GoRoute(
                  path: '/settings/theme',
                  builder: (_, __) => _page('Theme page')),
              GoRoute(
                  path: '/admin/branches',
                  builder: (_, __) => _page('Branches page')),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: _authOverrides(),
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();

      Future<void> openDrawer() async {
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer), findsOneWidget);
      }

      Future<void> tapDrawerItem(String label, String expectedText) async {
        await openDrawer();
        final item = find.widgetWithText(ListTile, label).last;
        await tester.scrollUntilVisible(item, 200,
            scrollable: find.byType(Scrollable).last);
        await tester.tap(item, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text(expectedText), findsWidgets);
        expect(find.text('Error'), findsNothing);
      }

      await tapDrawerItem('New sale', 'POS page');
      await tapDrawerItem('Inventory', 'Inventory page');
      await tapDrawerItem('Purchasing', 'Purchasing page');
      await tapDrawerItem('Expenses', 'Expenses page');
      await tapDrawerItem('Pharmacy value', 'Pharmacy value page');
      await tapDrawerItem(
          'Expected expenses and overdue', 'Expected expenses page');
      await tapDrawerItem('Staff list and status', 'Users page');
      await tapDrawerItem('My profile', 'Profile page');
      await tapDrawerItem('Change password', 'Change password page');
      await tapDrawerItem('Theme', 'Theme page');
    });

    testWidgets(
        'dashboard top cards side by side without overflow ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      _setSize(tester, size);
      final errors = _captureOverflow();
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(
              path: '/dashboard/pharmacy-value',
              builder: (_, __) => const Scaffold(body: Text('value'))),
          GoRoute(
              path: '/dashboard/expected-expenses',
              builder: (_, __) => const Scaffold(body: Text('expenses'))),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._authOverrides(),
          dashboardPharmacyValueProvider.overrideWith((ref) async =>
              const DashboardPharmacyValueSummary(cost: 12345, retail: 23456)),
          dashboardExpectedExpensesProvider.overrideWith((ref) async =>
              const DashboardExpectedExpenseSummary(
                  total: 5000, overdue: 1200)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pharmacy value'), findsWidgets);
      expect(find.text('Expected expenses'), findsWidgets);
      final overflows = errors
          .where((e) => e.exceptionAsString().contains('overflowed'))
          .toList();
      expect(overflows, isEmpty,
          reason: overflows.map((e) => e.exceptionAsString()).join('\n'));
    });
  }

  testWidgets('change password form validates input', (tester) async {
    _setSize(tester, const Size(412, 915));
    await tester.pumpWidget(ProviderScope(
      overrides: _authOverrides(),
      child: const MaterialApp(home: ChangePasswordScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(3));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'), 'oldpass');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), '123');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'), '456');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('adding an expense updates the list and the total',
      (tester) async {
    _setSize(tester, const Size(412, 915));
    await tester.pumpWidget(ProviderScope(
      overrides: _authOverrides(),
      child: const MaterialApp(
        home: ExpensesScreen(initialRows: [
          {
            'id': 'e1',
            'category': 'Rent',
            'amount': 1000,
            'expense_date': '2026-11-01T00:00:00.000Z',
            'description': 'Office rent',
            'payment_method': 'cash',
            'status': 'approved',
            'created_by': 'u1',
          }
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Office rent'), findsOneWidget);

    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    // Amount is first field in dialog, Description is later
    await tester.enterText(fields.at(0), '500');
    await tester.enterText(fields.last, 'Transport cost');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Transport cost'), findsOneWidget);
    expect(find.textContaining('500'), findsWidgets);
  });
}
