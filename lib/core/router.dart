import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/audit_screen.dart';
import '../features/admin/branches_screen.dart';
import '../features/admin/settings_screen.dart';
import '../features/admin/team_access_screen.dart';
import '../features/admin/users_screen.dart';
import '../features/auth/forbidden_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_error_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/customers/customers_routes.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/expected_expenses_screen.dart';
import '../features/dashboard/pharmacy_value_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/inventory/inventory_routes.dart';
import '../features/pos/pos_routes.dart';
import '../features/prescriptions/prescriptions_routes.dart';
import '../features/purchasing/purchasing_routes.dart';
import '../features/reports/reports_screen.dart';
import '../features/sales/sales_routes.dart';
import '../features/shifts/shifts_routes.dart';
import '../features/suppliers/suppliers_routes.dart';
import 'auth/auth_controller.dart';
import 'nav/app_shell.dart';
import 'nav/menu_items.dart';
import 'permissions.dart';
import 'strings.dart';
import 'theme/app_colors.dart';
import 'widgets.dart';

Page<void> _fadePage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

RouteBase _withTransition(RouteBase route) {
  if (route is GoRoute) {
    final builder = route.builder;
    final pageBuilder = route.pageBuilder;
    // ignore: prefer_const_declarations
    final goRoute = GoRoute.new;
    return goRoute(
      path: route.path,
      name: route.name,
      parentNavigatorKey: route.parentNavigatorKey,
      redirect: route.redirect,
      routes: route.routes.map(_withTransition).toList(),
      pageBuilder: pageBuilder ??
          (builder == null
              ? null
              : (context, state) =>
                  _fadePage(state: state, child: builder(context, state))),
    );
  }
  if (route is ShellRoute) {
    return ShellRoute(
      navigatorKey: route.navigatorKey,
      builder: route.builder,
      pageBuilder: route.pageBuilder,
      routes: route.routes.map(_withTransition).toList(),
    );
  }
  return route;
}

List<RouteBase> _withTransitions(List<RouteBase> routes) =>
    routes.map(_withTransition).toList();

/// The single router for the whole app. A screens own the routes under
/// /dashboard, /admin, /expenses, /reports and /profile; every other feature
/// contributes its own route list, which Agent A only wires in here.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: homeFor(ref.read(authProvider).profile?.role),
    // Bumping this notifier after auth changes makes go_router re-run redirect.
    refreshListenable: authRevision,
    redirect: (context, state) =>
        redirectFor(ref.read(authProvider), state.uri.path),
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_off_outlined,
                    size: 52, color: AppColors.gold500),
                const SizedBox(height: 16),
                Text(S.notFoundTitle,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(S.notFoundBody),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: S.backToHome,
                  width: 200,
                  onPressed: () {
                    final auth = ref.read(authProvider);
                    context.go(homeFor(auth.profile?.role));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    routes: _withTransitions([
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/forbidden',
        builder: (context, state) => const ForbiddenScreen(),
      ),
      GoRoute(
        path: '/profile_error',
        builder: (context, state) => const ProfileErrorScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
            routes: [
              GoRoute(
                path: 'pharmacy-value',
                builder: (context, state) => const PharmacyValueScreen(),
              ),
              GoRoute(
                path: 'expected-expenses',
                builder: (context, state) => const ExpectedExpensesScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/expenses',
            builder: (context, state) => const ExpensesScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/admin/team',
            builder: (context, state) => const TeamAccessScreen(),
          ),
          GoRoute(
            path: '/admin/branches',
            builder: (context, state) => const BranchesScreen(),
          ),
          GoRoute(
            path: '/admin/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/admin/audit',
            builder: (context, state) => const AuditScreen(),
          ),
          ...posRoutes,
          ...inventoryRoutes,
          ...purchasingRoutes,
          ...salesRoutes,
          ...shiftsRoutes,
          ...customersRoutes,
          ...prescriptionsRoutes,
          ...suppliersRoutes,
        ],
      ),
    ]),
  );
});

const Set<String> _publicPaths = {
  '/login',
  '/forgot-password',
  '/reset-password',
};

/// Exportable so tests can assert every route maps to the intended module.
String? moduleForLocation(String location) {
  // Most specific routes first; the generic menu-prefix loop below is only a
  // fallback for screens that live directly under a module path.
  if (location == '/sales/returns' || location.startsWith('/sales/returns/')) {
    return Modules.saleReturns;
  }
  const stockPaths = [
    '/inventory/batches',
    '/inventory/adjustments',
    '/inventory/movements',
    '/inventory/alerts',
    '/inventory/stocktake',
  ];
  for (final path in stockPaths) {
    if (location == path || location.startsWith('$path/')) return Modules.stock;
  }
  for (final item in allMenuItems) {
    if (location == item.path || location.startsWith('${item.path}/')) {
      return item.module;
    }
  }
  return null;
}

/// Pure redirect logic, kept public so it can be unit-tested without a router.
String? redirectFor(AuthState auth, String location) {
  final waiting = auth.status == AuthStatus.initial ||
      auth.status == AuthStatus.loading ||
      auth.status == AuthStatus.profileLoading;

  if (_publicPaths.contains(location)) {
    if (location == '/login' &&
        auth.status == AuthStatus.authenticated &&
        auth.profile?.isActive == true) {
      return homeFor(auth.profile!.role);
    }
    return null;
  }

  if (location == '/profile_error') {
    if (auth.status == AuthStatus.unauthenticated) return '/login';
    if (waiting) return null;
    if (auth.status == AuthStatus.authenticated &&
        auth.profile?.isActive == true) {
      return homeFor(auth.profile!.role);
    }
    return null;
  }

  if (location == '/forbidden') {
    if (auth.status == AuthStatus.unauthenticated || waiting) return '/login';
    if (auth.status == AuthStatus.profileError) return '/profile_error';
    if (auth.status == AuthStatus.authenticated &&
        auth.profile?.isActive == true) {
      return homeFor(auth.profile!.role);
    }
    return null;
  }

  // Wait for both session and profile before deciding where to send anyone.
  if (waiting) return null;
  // An expired token always lands on sign-in, whatever screen was open.
  if (auth.sessionExpired) {
    return _publicPaths.contains(location) ? null : '/login';
  }
  if (auth.status == AuthStatus.profileError) return '/profile_error';
  if (auth.status != AuthStatus.authenticated) return '/login';
  if (auth.profile?.isActive != true) return '/forbidden';

  final module = moduleForLocation(location);
  if (module != null && !can(auth.profile!.role, module, PermAction.view)) {
    return '/forbidden';
  }
  return null;
}
