// Roles and the exact permission matrix from the shared contract.
// This is pure logic so it can be unit-tested without Supabase or Flutter.

enum AppRole {
  superAdmin,
  admin,
  pharmacist,
  cashier,
  storeKeeper,
  accountant,
}

extension AppRoleX on AppRole {
  String get dbName => switch (this) {
        AppRole.superAdmin => 'super_admin',
        AppRole.admin => 'admin',
        AppRole.pharmacist => 'pharmacist',
        AppRole.cashier => 'cashier',
        AppRole.storeKeeper => 'store_keeper',
        AppRole.accountant => 'accountant',
      };

  String get label => switch (this) {
        AppRole.superAdmin => 'Super admin',
        AppRole.admin => 'Admin',
        AppRole.pharmacist => 'Pharmacist',
        AppRole.cashier => 'Cashier',
        AppRole.storeKeeper => 'Store keeper',
        AppRole.accountant => 'Accountant',
      };

  static AppRole? fromDb(String? value) => switch (value) {
        'super_admin' => AppRole.superAdmin,
        'admin' => AppRole.admin,
        'pharmacist' => AppRole.pharmacist,
        'cashier' => AppRole.cashier,
        'store_keeper' => AppRole.storeKeeper,
        'accountant' => AppRole.accountant,
        _ => null,
      };
}

/// E = edit, V = view, own = own records only, - = none.
enum Perm { edit, view, own, none }

enum PermAction { view, edit }

abstract final class Modules {
  static const dashboard = 'dashboard';
  static const users = 'users';

  /// Extension to the contract matrix: super-admin-only team access sharing.
  static const teamAccess = 'teamAccess';
  static const branches = 'branches';
  static const settings = 'settings';
  static const audit = 'audit';
  static const medicines = 'medicines';
  static const stock = 'stock';
  static const suppliers = 'suppliers';
  static const purchaseOrders = 'purchaseOrders';
  static const pos = 'pos';
  static const sales = 'sales';
  static const saleReturns = 'saleReturns';
  static const shifts = 'shifts';
  static const customers = 'customers';
  static const prescriptions = 'prescriptions';
  static const expenses = 'expenses';
  static const reports = 'reports';
}

const _e = Perm.edit;
const _v = Perm.view;
const _o = Perm.own;
const _n = Perm.none;

/// module             S   A   P   C    K   F
const Map<String, Map<AppRole, Perm>> permissionMatrix = {
  Modules.dashboard: {
    AppRole.superAdmin: _v,
    AppRole.admin: _v,
    AppRole.pharmacist: _v,
    AppRole.cashier: _v,
    AppRole.storeKeeper: _v,
    AppRole.accountant: _v,
  },
  Modules.users: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.teamAccess: {
    AppRole.superAdmin: _e,
    AppRole.admin: _v,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.branches: {
    AppRole.superAdmin: _e,
    AppRole.admin: _v,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.settings: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.audit: {
    AppRole.superAdmin: _v,
    AppRole.admin: _v,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.medicines: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _v,
    AppRole.storeKeeper: _e,
    AppRole.accountant: _v,
  },
  Modules.stock: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _v,
    AppRole.storeKeeper: _e,
    AppRole.accountant: _v,
  },
  Modules.suppliers: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _e,
    AppRole.accountant: _v,
  },
  Modules.purchaseOrders: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _e,
    AppRole.accountant: _v,
  },
  Modules.pos: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _e,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.sales: {
    AppRole.superAdmin: _e,
    AppRole.admin: _v,
    AppRole.pharmacist: _v,
    AppRole.cashier: _o,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _v,
  },
  Modules.saleReturns: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.shifts: {
    AppRole.superAdmin: _e,
    AppRole.admin: _v,
    AppRole.pharmacist: _v,
    AppRole.cashier: _o,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _v,
  },
  Modules.customers: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _e,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _v,
  },
  Modules.prescriptions: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _e,
    AppRole.cashier: _v,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _n,
  },
  Modules.expenses: {
    AppRole.superAdmin: _e,
    AppRole.admin: _e,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _e,
  },
  Modules.reports: {
    AppRole.superAdmin: _e,
    AppRole.admin: _v,
    AppRole.pharmacist: _n,
    AppRole.cashier: _n,
    AppRole.storeKeeper: _n,
    AppRole.accountant: _v,
  },
};

Perm permissionFor(AppRole role, String module) =>
    permissionMatrix[module]?[role] ?? Perm.none;

/// View includes edit and own records; edit means full edit rights only.
bool can(AppRole role, String module, PermAction action) {
  final perm = permissionFor(role, module);
  return switch (action) {
    PermAction.view =>
      perm == Perm.edit || perm == Perm.view || perm == Perm.own,
    PermAction.edit => perm == Perm.edit,
  };
}

/// True when the role may only see records belonging to themselves.
bool isOwnOnly(AppRole role, String module) =>
    permissionFor(role, module) == Perm.own;

/// super_admin sees every branch; everyone else is scoped to their branch.
bool canSeeAllBranches(AppRole role) => role == AppRole.superAdmin;

/// Admins may manage users in their own branch but never a super_admin.
bool canManageUser(AppRole actor, AppRole target) {
  if (!can(actor, Modules.users, PermAction.edit)) return false;
  if (target == AppRole.superAdmin && actor != AppRole.superAdmin) return false;
  return true;
}

/// Dashboard overview visibility is deliberately narrower than raw module
/// access: a cashier gets their own counters, a store keeper gets stock, and
/// whole-pharmacy valuations stay with finance/admin roles.
bool canSeeDashboardPharmacyValue(AppRole role) =>
    can(role, Modules.reports, PermAction.view);

bool canSeeDashboardExpectedExpenses(AppRole role) =>
    role == AppRole.superAdmin || role == AppRole.admin;

bool canSeeDashboardStock(AppRole role) =>
    can(role, Modules.stock, PermAction.edit);
