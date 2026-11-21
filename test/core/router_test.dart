import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/nav/menu_items.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/router.dart';

AuthState _signedIn(AppRole role, {bool active = true}) => AuthState(
      status: AuthStatus.authenticated,
      profile: UserProfile(
        id: 'user-1',
        email: 'staff@yusra.test',
        fullName: 'Test User',
        role: role,
        isActive: active,
      ),
    );

void main() {
  group('authentication redirects', () {
    test('signed-out users are sent to login for every protected route', () {
      for (final path in [
        '/dashboard',
        '/inventory/medicines',
        '/admin/users',
        '/reports',
        '/profile',
      ]) {
        expect(redirectFor(AuthState.unauthenticated, path), '/login',
            reason: path);
      }
    });

    test('initial, loading and profile-loading states wait for the profile',
        () {
      expect(redirectFor(AuthState.initial, '/dashboard'), isNull);
      expect(redirectFor(AuthState.loading, '/dashboard'), isNull);
      expect(
          redirectFor(
              const AuthState(status: AuthStatus.profileLoading), '/dashboard'),
          isNull);
    });

    test('signed-in users go to their role home away from login', () {
      for (final role in AppRole.values) {
        expect(redirectFor(_signedIn(role), '/login'), homeFor(role),
            reason: role.name);
      }
      expect(redirectFor(_signedIn(AppRole.cashier, active: false), '/login'),
          isNull);
    });

    test('forgot/reset password are always reachable', () {
      expect(
          redirectFor(AuthState.unauthenticated, '/forgot-password'), isNull);
      expect(redirectFor(AuthState.unauthenticated, '/reset-password'), isNull);
      expect(redirectFor(_signedIn(AppRole.admin), '/forgot-password'), isNull);
    });
  });

  group('profile load failures', () {
    const profileError = AuthState(
      status: AuthStatus.profileError,
      error: 'The profile service is unavailable.',
    );

    test('profile errors get a dedicated screen, not access denied', () {
      expect(redirectFor(profileError, '/dashboard'), '/profile_error');
      expect(redirectFor(profileError, '/profile_error'), isNull);
      expect(redirectFor(profileError, '/forbidden'), '/profile_error');
    });

    test('the profile error screen is not a redirect loop', () {
      expect(redirectFor(_signedIn(AppRole.cashier), '/profile_error'), '/pos');
      expect(
          redirectFor(AuthState.unauthenticated, '/profile_error'), '/login');
    });
  });

  group('account status and role guards', () {
    test('inactive accounts only reach the forbidden page', () {
      final inactive = _signedIn(AppRole.admin, active: false);
      expect(redirectFor(inactive, '/dashboard'), '/forbidden');
      expect(redirectFor(inactive, '/forbidden'), isNull);
    });

    test('signed-out users cannot stay on the forbidden page', () {
      expect(redirectFor(AuthState.unauthenticated, '/forbidden'), '/login');
    });

    test('active users are never trapped on the forbidden page', () {
      for (final role in AppRole.values) {
        expect(redirectFor(_signedIn(role), '/forbidden'), homeFor(role),
            reason: role.name);
      }
    });

    test('cashier is blocked from admin, expenses, returns and reports', () {
      final cashier = _signedIn(AppRole.cashier);
      expect(redirectFor(cashier, '/pos'), isNull);
      expect(redirectFor(cashier, '/inventory/medicines'), isNull);
      expect(redirectFor(cashier, '/expenses'), '/forbidden');
      expect(redirectFor(cashier, '/reports'), '/forbidden');
      expect(redirectFor(cashier, '/admin/users'), '/forbidden');
      expect(redirectFor(cashier, '/sales/returns'), '/forbidden');
    });

    test('accountant and admin reach their permitted modules', () {
      expect(redirectFor(_signedIn(AppRole.accountant), '/reports'), isNull);
      expect(redirectFor(_signedIn(AppRole.accountant), '/expenses'), isNull);
      expect(redirectFor(_signedIn(AppRole.admin), '/admin/users'), isNull);
      expect(redirectFor(_signedIn(AppRole.superAdmin), '/admin/branches'),
          isNull);
    });

    test('unknown routes are left to the router 404 builder', () {
      expect(redirectFor(_signedIn(AppRole.admin), '/not-a-route'), isNull);
    });
  });

  group('role homes and module mapping', () {
    test('every role home is permitted and navigable', () {
      for (final role in AppRole.values) {
        final home = homeFor(role);
        final module = moduleForLocation(home);
        expect(module, isNotNull, reason: role.name);
        expect(can(role, module!, PermAction.view), isTrue, reason: role.name);
        expect(redirectFor(_signedIn(role), home), isNull, reason: role.name);
      }
    });

    test('specific routes override generic menu prefixes', () {
      expect(moduleForLocation('/sales/returns'), Modules.saleReturns);
      expect(moduleForLocation('/sales/returns/abc'), Modules.saleReturns);
      expect(moduleForLocation('/sales'), Modules.sales);
      expect(moduleForLocation('/inventory/batches'), Modules.stock);
      expect(moduleForLocation('/inventory/medicines/1'), Modules.medicines);
    });
  });
}
