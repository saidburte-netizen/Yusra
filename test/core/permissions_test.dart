import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/nav/menu_items.dart';
import 'package:yusra_pharmacy/core/permissions.dart';
import 'package:yusra_pharmacy/core/strings.dart';

void main() {
  group('AppRole mapping', () {
    test('db names round-trip through fromDb', () {
      for (final role in AppRole.values) {
        expect(AppRoleX.fromDb(role.dbName), role, reason: role.label);
      }
      expect(AppRoleX.fromDb('unknown'), isNull);
      expect(AppRoleX.fromDb(null), isNull);
    });
  });

  group('permission matrix', () {
    test('team access sharing is super-admin editable and admin view-only', () {
      expect(
        can(AppRole.superAdmin, Modules.teamAccess, PermAction.edit),
        isTrue,
      );
      expect(can(AppRole.admin, Modules.teamAccess, PermAction.view), isTrue);
      expect(can(AppRole.admin, Modules.teamAccess, PermAction.edit), isFalse);
      expect(can(AppRole.cashier, Modules.teamAccess, PermAction.view), isFalse);
    });

    test('cashiers can use POS but not expenses or reports', () {
      expect(can(AppRole.cashier, Modules.pos, PermAction.edit), isTrue);
      expect(can(AppRole.cashier, Modules.medicines, PermAction.view), isTrue);
      expect(can(AppRole.cashier, Modules.expenses, PermAction.view), isFalse);
      expect(can(AppRole.cashier, Modules.reports, PermAction.view), isFalse);
      expect(can(AppRole.cashier, Modules.users, PermAction.view), isFalse);
    });

    test('cost prices stay hidden from cashiers and accountants', () {
      // The catalogue screen uses this flag to mask the cost column.
      expect(permissionFor(AppRole.cashier, Modules.medicines), Perm.view);
      expect(permissionFor(AppRole.accountant, Modules.medicines), Perm.view);
      expect(permissionFor(AppRole.pharmacist, Modules.medicines), Perm.edit);
    });

    test('pharmacists and store keepers may edit stock, cashiers may not', () {
      expect(can(AppRole.pharmacist, Modules.stock, PermAction.edit), isTrue);
      expect(can(AppRole.storeKeeper, Modules.stock, PermAction.edit), isTrue);
      expect(can(AppRole.cashier, Modules.stock, PermAction.edit), isFalse);
      expect(can(AppRole.cashier, Modules.stock, PermAction.view), isTrue);
    });

    test('accountants view reports and edit expenses', () {
      expect(can(AppRole.accountant, Modules.reports, PermAction.view), isTrue);
      expect(can(AppRole.accountant, Modules.reports, PermAction.edit), isFalse);
      expect(can(AppRole.accountant, Modules.expenses, PermAction.edit), isTrue);
    });

    test('only super admins and admins manage users', () {
      expect(can(AppRole.superAdmin, Modules.users, PermAction.edit), isTrue);
      expect(can(AppRole.admin, Modules.users, PermAction.edit), isTrue);
      expect(can(AppRole.pharmacist, Modules.users, PermAction.view), isFalse);
    });

    test('unknown modules and roles deny access', () {
      expect(permissionFor(AppRole.superAdmin, 'does_not_exist'), Perm.none);
      expect(can(AppRole.superAdmin, 'does_not_exist', PermAction.view), isFalse);
    });
  });

  group('ownership and branch scope', () {
    test('cashiers only see their own sales and shifts', () {
      expect(isOwnOnly(AppRole.cashier, Modules.sales), isTrue);
      expect(isOwnOnly(AppRole.cashier, Modules.shifts), isTrue);
      expect(isOwnOnly(AppRole.admin, Modules.sales), isFalse);
      expect(isOwnOnly(AppRole.cashier, Modules.pos), isFalse);
    });

    test('only super admins see every branch', () {
      expect(canSeeAllBranches(AppRole.superAdmin), isTrue);
      for (final role in AppRole.values) {
        if (role == AppRole.superAdmin) continue;
        expect(canSeeAllBranches(role), isFalse, reason: role.label);
      }
    });

    test('nobody except a super admin can manage a super admin', () {
      expect(canManageUser(AppRole.superAdmin, AppRole.superAdmin), isTrue);
      expect(canManageUser(AppRole.admin, AppRole.superAdmin), isFalse);
      expect(canManageUser(AppRole.admin, AppRole.cashier), isTrue);
      expect(canManageUser(AppRole.pharmacist, AppRole.cashier), isFalse);
    });
  });

  group('navigation', () {
    test('menu is filtered by permission and has unique paths', () {
      final paths = allMenuItems.map((item) => item.path).toList();
      expect(paths.toSet().length, paths.length);

      final cashier = menuFor(AppRole.cashier).map((item) => item.path).toList();
      expect(cashier, contains('/pos'));
      expect(cashier, contains('/dashboard'));
      expect(cashier, isNot(contains('/expenses')));
      expect(cashier, isNot(contains('/admin/users')));

      final superAdmin = menuFor(AppRole.superAdmin);
      expect(superAdmin.length, allMenuItems.length);
    });

    test('bottom navigation never exceeds four items', () {
      for (final role in AppRole.values) {
        expect(bottomNavItems(role).length, lessThanOrEqualTo(4));
      }
      expect(bottomNavItems(AppRole.cashier).first.path, '/dashboard');
    });

    test('titles resolve for nested admin routes', () {
      expect(titleForLocation('/admin/users'), S.users);
      expect(titleForLocation('/inventory/medicines/42'), S.inventory);
      expect(titleForLocation('/admin/unknown'), S.admin);
    });
  });
}
