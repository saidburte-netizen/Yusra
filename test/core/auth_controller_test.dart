import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/auth/auth_controller.dart';
import 'package:yusra_pharmacy/core/permissions.dart';

void main() {
  test('a missing or invalid role cannot be turned into a cashier', () {
    expect(
      () => UserProfile.fromJson(
        {'id': 'u1', 'role': 'not_a_role', 'is_active': true},
        email: 'u1@yusra.test',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserProfile.fromJson(
        {'id': 'u1', 'role': 'cashier'},
        email: 'u1@yusra.test',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a valid profile is parsed without fabricating a role', () {
    final profile = UserProfile.fromJson(
      {
        'id': 'u1',
        'role': 'store_keeper',
        'is_active': true,
        'full_name': 'Store Keeper',
        'branch_id': 'b1',
      },
      email: 'u1@yusra.test',
    );
    expect(profile.role, AppRole.storeKeeper);
    expect(profile.roleLabel, 'store_keeper');
    expect(profile.isActive, isTrue);
    expect(profile.branchId, 'b1');
  });

  test('profileError state has no profile at all', () {
    const state = AuthState(
      status: AuthStatus.profileError,
      error: 'Could not read the account.',
    );
    expect(state.profile, isNull);
    expect(state.isAuthenticated, isFalse);
  });
}
