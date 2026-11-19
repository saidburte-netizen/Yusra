import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
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

    test('loading and initial states also wait at login', () {
      expect(redirectFor(AuthState.initial, '/dashboard'), '/login');
      expect(redirectFor(AuthState.loading, '/dashboard'), '/login');
    });

    test('signed-in users are bounced away from login', () {
      expect(redirectFor(_signedIn(AppRole.cashier), '/login'), '/dashboard');
      expect(
          redirectFor(_signedIn(AppRole.cashier, active: false), '/login'), isNull);
    });

    test('forgot/reset password are always reachable', () {
      expect(redirectFor(AuthState.unauthenticated, '/forgot-password'), isNull);
      expect(redirectFor(AuthState.unauthenticated, '/reset-password'), isNull);
      expect(redirectFor(_signedIn(AppRole.admin), '/forgot-password'), isNull);
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

    test('cashier is blocked from admin, expenses and reports', () {
      final cashier = _signedIn(AppRole.cashier);
      expect(redirectFor(cashier, '/pos'), isNull);
      expect(redirectFor(cashier, '/inventory/medicines'), isNull);
      expect(redirectFor(cashier, '/expenses'), '/forbidden');
      expect(redirectFor(cashier, '/reports'), '/forbidden');
      expect(redirectFor(cashier, '/admin/users'), '/forbidden');
    });

    test('permission guards also cover nested feature routes', () {
      final pharmacist = _signedIn(AppRole.pharmacist);
      expect(redirectFor(pharmacist, '/admin/audit'), '/forbidden');
      expect(redirectFor(pharmacist, '/inventory/batches'), isNull);
      expect(redirectFor(pharmacist, '/expenses'), '/forbidden');
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
}
