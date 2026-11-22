import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/nav/app_shell.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/theme/app_theme.dart';
import 'package:yusra_pharmacy/core/theme/theme_mode_controller.dart';
import 'package:yusra_pharmacy/core/widgets/theme_mode_toggle.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      profile: UserProfile(
        id: 'u1',
        email: 'admin@yusra.test',
        role: AppRole.admin,
        branchId: 'b1',
        fullName: 'Admin User',
        isActive: true,
      ),
    );
  }

  @override
  Future<void> bootstrap() async {}
}

Widget _shellApp() {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) =>
                const Scaffold(body: Text('Dashboard body')),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) =>
                const Scaffold(body: Text('Profile body')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthController()),
      themeModeProvider.overrideWith((ref) => ThemeModeController()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeController', () {
    test('persists and restores theme mode', () async {
      SharedPreferences.setMockInitialValues({'yusra.theme_mode': 'dark'});
      final controller = ThemeModeController();
      await controller.load();
      expect(controller.state, ThemeMode.dark);
      await controller.setMode(ThemeMode.light);
      expect(controller.state, ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('yusra.theme_mode'), 'light');
    });
  });

  group('ThemeModeToggle', () {
    testWidgets('shows light/dark/system choices and updates mode',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeModeProvider.overrideWith((ref) => ThemeModeController()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: const Scaffold(
                body: Center(
                    child: SizedBox(width: 320, child: ThemeModeToggle()))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ThemeModeToggle)),
      );
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('golden - theme toggle light', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(360, 120));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeModeProvider.overrideWith((ref) => ThemeModeController())
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.light,
            home: const Scaffold(
                body: Center(
                    child: SizedBox(width: 320, child: ThemeModeToggle()))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(ThemeModeToggle),
        matchesGoldenFile('goldens/theme_toggle_light.png'),
      );
    });
  });

  group('App themes', () {
    testWidgets('light and dark themes render distinctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Card(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Card content'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Card content'))).brightness,
          Brightness.light);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: Card(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Card content'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Card content'))).brightness,
          Brightness.dark);
    });

    testWidgets('golden - light theme card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Yusra Pharmacy',
                      style: ThemeData.light().textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Premium card'))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(Scaffold), matchesGoldenFile('goldens/theme_light.png'));
    });

    testWidgets('golden - dark theme card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Yusra Pharmacy',
                      style: ThemeData.dark().textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Premium card'))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(Scaffold), matchesGoldenFile('goldens/theme_dark.png'));
    });
  });

  group('AppShell', () {
    testWidgets('renders single shell structure and navigation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_shellApp());
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Dashboard body'), findsOneWidget);
      // Shell should show a primary navigation pattern.
      final rails = find.byType(NavigationRail).evaluate().length;
      final bars = find.byType(NavigationBar).evaluate().length;
      final customBottom =
          find.byIcon(Icons.dashboard_outlined).evaluate().isNotEmpty;
      expect(rails + bars >= 1 || customBottom, isTrue);
    });
  });
}
