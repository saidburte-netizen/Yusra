import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/nav/app_shell.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/strings.dart';
import 'package:yusra_pharmacy/core/widgets/display.dart';

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

List<Override> authOverrides(AppRole role) => [
      authProvider.overrideWith((ref) {
        final controller = AuthController();
        controller.state = AuthState(
          status: AuthStatus.authenticated,
          profile: UserProfile(
            id: 'user-1',
            email: 'cashier@yusra.test',
            fullName: 'Asmara Tesfa',
            role: role,
            isActive: true,
            branchId: 'branch-1',
          ),
        );
        return controller;
      }),
    ];

void main() {
  const sizes = <({String name, Size size})>[
    (name: '360x640', size: Size(360, 640)),
    (name: '412x915', size: Size(412, 915)),
  ];

  for (final viewport in sizes) {
    testWidgets('PageHeader stacks title and actions at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();
      const title = 'Purchasing and supplier invoices';

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PageHeader(
                title: title,
                subtitle: 'Today · Yusra Pharmacy',
                actions: [
                  SizedBox(
                    width: 120,
                    child: Text(S.timeRange, textAlign: TextAlign.center),
                  ),
                  Icon(Icons.refresh),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text(title), findsOneWidget);
      final titleRect = tester.getRect(find.text(title));
      final actionRect = tester.getRect(find.text(S.timeRange));
      expect(titleRect.top, lessThan(actionRect.top));
      // A whole phrase, not one word per line.
      expect(titleRect.height, lessThan(100));
    });

    testWidgets('TopBar keeps title and actions on one row at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authOverrides(AppRole.superAdmin),
          child: const MaterialApp(
            home: Scaffold(
              appBar: TopBar(title: 'Sales history', narrow: true),
              body: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.text('Sales history'), findsOneWidget);
      final titleRect = tester.getRect(find.text('Sales history'));
      final bellRect = tester.getRect(find.byTooltip(S.alerts));
      // Single-row top bar: title and actions share the same row.
      expect(titleRect.top, lessThan(bellRect.bottom));
      expect(titleRect.bottom, greaterThan(bellRect.top));
    });

    testWidgets('ResponsiveGrid does not overflow at ${viewport.name}',
        (tester) async {
      setTestSize(tester, viewport.size);
      final errors = captureFlutterErrors();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResponsiveGrid(
                children: [
                  SizedBox(height: 80, child: Card()),
                  SizedBox(height: 80, child: Card()),
                  SizedBox(height: 80, child: Card()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(errors, isEmpty, reason: '${errors.map((e) => e.exception)}');
      expect(find.byType(Card), findsNWidgets(3));
    });
  }
}
