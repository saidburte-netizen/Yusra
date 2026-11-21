import 'package:flutter/material.dart';

import '../permissions.dart';
import '../strings.dart';

class MenuItem {
  const MenuItem({
    required this.label,
    required this.icon,
    required this.path,
    required this.module,
  });

  final String label;
  final IconData icon;
  final String path;
  final String module;
}

/// Every route from the contract appears exactly once. Visibility is filtered
/// by the permission matrix, never hard-coded per screen.
const List<MenuItem> allMenuItems = [
  MenuItem(
      label: S.dashboard,
      icon: Icons.dashboard_outlined,
      path: '/dashboard',
      module: Modules.dashboard),
  MenuItem(
      label: S.pos,
      icon: Icons.point_of_sale,
      path: '/pos',
      module: Modules.pos),
  MenuItem(
      label: S.inventory,
      icon: Icons.inventory_2_outlined,
      path: '/inventory',
      module: Modules.medicines),
  MenuItem(
      label: S.purchasing,
      icon: Icons.shopping_cart_outlined,
      path: '/purchasing/orders',
      module: Modules.purchaseOrders),
  MenuItem(
      label: S.sales,
      icon: Icons.receipt_long_outlined,
      path: '/sales',
      module: Modules.sales),
  MenuItem(
      label: S.shifts,
      icon: Icons.access_time_outlined,
      path: '/shifts',
      module: Modules.shifts),
  MenuItem(
      label: S.customers,
      icon: Icons.people_outline,
      path: '/customers',
      module: Modules.customers),
  MenuItem(
      label: S.prescriptions,
      icon: Icons.description_outlined,
      path: '/prescriptions',
      module: Modules.prescriptions),
  MenuItem(
      label: S.suppliers,
      icon: Icons.local_shipping_outlined,
      path: '/suppliers',
      module: Modules.suppliers),
  MenuItem(
      label: S.expenses,
      icon: Icons.account_balance_wallet_outlined,
      path: '/expenses',
      module: Modules.expenses),
  MenuItem(
      label: S.reports,
      icon: Icons.analytics_outlined,
      path: '/reports',
      module: Modules.reports),
  MenuItem(
      label: S.users,
      icon: Icons.manage_accounts_outlined,
      path: '/admin/users',
      module: Modules.users),
  MenuItem(
      label: S.teamAccess,
      icon: Icons.group_add_outlined,
      path: '/admin/team',
      module: Modules.teamAccess),
  MenuItem(
      label: S.branches,
      icon: Icons.account_balance_outlined,
      path: '/admin/branches',
      module: Modules.branches),
  MenuItem(
      label: S.settings,
      icon: Icons.settings_outlined,
      path: '/admin/settings',
      module: Modules.settings),
  MenuItem(
      label: S.audit,
      icon: Icons.history_outlined,
      path: '/admin/audit',
      module: Modules.audit),
];

const List<String> _preferredBottomNav = [
  '/dashboard',
  '/pos',
  '/inventory',
  '/sales',
];

List<MenuItem> menuFor(AppRole role) => allMenuItems
    .where((item) => can(role, item.module, PermAction.view))
    .toList();

/// Where each role lands after sign-in and after recovery from an error.
/// Every returned path is guaranteed to be permitted by [can] for that role.
String homeFor(AppRole? role) => switch (role) {
      AppRole.cashier => '/pos',
      AppRole.storeKeeper => '/inventory',
      AppRole.accountant => '/reports',
      AppRole.pharmacist => '/prescriptions',
      AppRole.admin || AppRole.superAdmin || null => '/dashboard',
    };

/// Phones get the four most used permitted items; the rest live in More.
List<MenuItem> bottomNavItems(AppRole role) {
  final permitted = menuFor(role);
  final selected = <MenuItem>[];
  for (final path in _preferredBottomNav) {
    final matches = permitted.where((item) => item.path == path).toList();
    if (matches.isNotEmpty) selected.add(matches.first);
  }
  for (final item in permitted) {
    if (selected.length >= 4) break;
    if (!selected.contains(item)) selected.add(item);
  }
  return selected.take(4).toList();
}

String titleForLocation(String location) {
  for (final item in allMenuItems) {
    if (location == item.path || location.startsWith('${item.path}/')) {
      return item.label;
    }
  }
  if (location.startsWith('/admin')) return S.admin;
  if (location == '/profile') return S.profile;
  if (location == '/dev/widgets') return S.widgetKit;
  return S.appName;
}
