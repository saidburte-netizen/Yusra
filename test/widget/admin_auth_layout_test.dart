import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/activity/activity.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/strings.dart';
import 'package:yusra_pharmacy/features/admin/audit_screen.dart';
import 'package:yusra_pharmacy/features/admin/branches_screen.dart';
import 'package:yusra_pharmacy/features/admin/settings_screen.dart';
import 'package:yusra_pharmacy/features/admin/team_access_screen.dart';
import 'package:yusra_pharmacy/features/admin/users_screen.dart';
import 'package:yusra_pharmacy/features/auth/forgot_password_screen.dart';
import 'package:yusra_pharmacy/features/auth/forbidden_screen.dart';
import 'package:yusra_pharmacy/features/auth/login_screen.dart';
import 'package:yusra_pharmacy/features/auth/profile_error_screen.dart';
import 'package:yusra_pharmacy/features/auth/profile_screen.dart';
import 'package:yusra_pharmacy/features/auth/reset_password_screen.dart';

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
            role: AppRole.superAdmin,
            isActive: true,
            branchId: 'branch-1',
            phone: '+251911000000',
          ),
        );
        return controller;
      }),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [..._overrides(), ...extraOverrides],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

List<Map<String, dynamic>> _branches() => [
      {'id': 'branch-1', 'name': 'Main branch', 'is_active': true},
      {'id': 'branch-2', 'name': 'Second branch', 'is_active': true},
    ];

List<Map<String, dynamic>> _users() => [
      {
        'id': 'user-1',
        'full_name': 'Asmara Tesfa',
        'email': 'cashier@yusra.test',
        'role': 'cashier',
        'branch_id': 'branch-1',
        'is_active': true,
      },
      {
        'id': 'user-2',
        'full_name': 'Nahom Gebre',
        'email': 'pharmacist@yusra.test',
        'role': 'pharmacist',
        'branch_id': 'branch-1',
        'is_active': false,
      },
      {
        'id': 'admin-1',
        'full_name': 'Admin User',
        'email': 'admin@yusra.test',
        'role': 'super_admin',
        'branch_id': 'branch-1',
        'is_active': true,
      },
    ];

List<Map<String, dynamic>> _settings() => [
      {'key': 'pharmacy_name', 'value': 'Yusra Pharmacy'},
      {'key': 'vat_rate', 'value': 15},
      {'key': 'low_stock_default', 'value': 10},
    ];

ActivityEntry _activity() => ActivityEntry(
      id: 'log-1',
      email: 'admin@yusra.test',
      role: 'super_admin',
      action: 'update',
      entityType: 'settings',
      entityId: 'pharmacy_name',
      createdAt: DateTime(2026, 11, 20, 9, 30),
      summary: 'Updated pharmacy name',
      branchId: 'branch-1',
    );

void main() {
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  for (final viewport in sizes) {
    testWidgets('LoginScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const LoginScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text(S.signIn), findsOneWidget);
    });

    testWidgets('ForbiddenScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const ForbiddenScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text(S.forbidden), findsOneWidget);
    });

    testWidgets('ProfileErrorScreen renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const ProfileErrorScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text(S.profileErrorTitle), findsOneWidget);
    });

    testWidgets('ForgotPasswordScreen renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const ForgotPasswordScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Reset password'), findsOneWidget);
    });

    testWidgets('ResetPasswordScreen renders at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const ResetPasswordScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Change password'), findsOneWidget);
    });

    testWidgets('ProfileScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, const ProfileScreen());
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Admin User'), findsWidgets);
    });

    testWidgets('UsersScreen renders all users at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        UsersScreen(initialUsers: _users(), initialBranches: _branches()),
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Asmara Tesfa'), findsOneWidget);
      expect(find.text('Nahom Gebre'), findsOneWidget);
      expect(find.text('Admin User'), findsOneWidget);
    });

    testWidgets('TeamAccessScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        TeamAccessScreen(
          initialMembers: _users(),
          initialBranches: _branches(),
        ),
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Nahom Gebre'), findsOneWidget);
    });

    testWidgets('BranchesScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, BranchesScreen(initialBranches: _branches()));
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Main branch'), findsOneWidget);
      expect(find.text('Second branch'), findsOneWidget);
    });

    testWidgets('SettingsScreen renders at ${viewport.name}', (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(tester, SettingsScreen(initialRows: _settings()));
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Yusra Pharmacy'), findsOneWidget);
    });

    testWidgets('AuditScreen renders entries at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      await _pump(
        tester,
        const AuditScreen(),
        extraOverrides: [
          activityProvider.overrideWith((ref) async => [_activity()]),
        ],
      );
      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.textContaining('settings update'), findsOneWidget);
    });
  }
}
