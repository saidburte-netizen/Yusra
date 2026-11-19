import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/audit_screen.dart';
import '../features/admin/branches_screen.dart';
import '../features/admin/settings_screen.dart';
import '../features/admin/users_screen.dart';
import '../features/auth/forbidden_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/customers/customers_routes.dart';
import '../features/dashboard/dashboard_screen.dart';
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

/// The single router for the whole app. A screens own the routes under
/// /dashboard, /admin, /expenses, /reports and /profile; every other feature
/// contributes its own route list, which Agent A only wires in here.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
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
                Text('404', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('This page does not exist.'),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: S.backToDashboard,
                  width: 200,
                  onPressed: () => context.go('/dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    routes: [
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
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
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
    ],
  );
});

const Set<String> _publicPaths = {
  '/login',
  '/forgot-password',
  '/reset-password',
};

/// Pure redirect logic, kept public so it can be unit-tested without a router.
String? redirectFor(AuthState auth, String location) {
  if (_publicPaths.contains(location)) {
    if (location == '/login' &&
        auth.status == AuthStatus.authenticated &&
        auth.profile?.isActive == true) {
      return '/dashboard';
    }
    return null;
  }

  if (location == '/forbidden') {
    if (auth.status == AuthStatus.unauthenticated ||
        auth.status == AuthStatus.initial) {
      return '/login';
    }
    return null;
  }

  if (auth.status != AuthStatus.authenticated) {
    return '/login';
  }
  if (auth.profile?.isActive != true) {
    return '/forbidden';
  }

  final module = _moduleFor(location);
  if (module != null &&
      !can(auth.profile!.role, module, PermAction.view)) {
    return '/forbidden';
  }
  return null;
}

/// Maps a location to the contract module used by the permission matrix.
String? _moduleFor(String location) {
  for (final item in allMenuItems) {
    if (location == item.path || location.startsWith('${item.path}/')) {
      return item.module;
    }
  }
  return null;
}
