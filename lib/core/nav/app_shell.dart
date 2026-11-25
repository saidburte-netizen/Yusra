import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../permissions.dart';
import '../strings.dart';
import '../supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets.dart';
import '../../features/inventory/data/drug_status_providers.dart';
import 'menu_items.dart';

/// Branch selected in the top bar by a super_admin (null = all branches).
final selectedBranchProvider = StateProvider<String?>((ref) => null);

/// Branch a super admin should work on before making an explicit choice.
/// Returns null when the user has already chosen, so we never overwrite them.
String? initialBranchId(
  List<Map<String, dynamic>> branches, {
  required String? ownBranchId,
  required bool touched,
  required String? selected,
}) {
  if (touched || selected != null || branches.isEmpty) return null;
  if (ownBranchId != null &&
      branches.any((branch) => branch['id'] == ownBranchId)) {
    return ownBranchId;
  }
  return branches.first['id'] as String?;
}

const _manageBranchesValue = '__manage_branches__';

/// True once the user has deliberately chosen a branch (including
/// "All branches"). Used to avoid overwriting an explicit choice when the
/// switcher rebuilds or the app is restarted.
final branchSelectionSetProvider = StateProvider<bool>((ref) => false);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(stockAlertRealtimeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final role = auth.profile?.role ?? AppRole.cashier;
    final items = menuFor(role);
    final location = GoRouterState.of(context).uri.path;
    final title = titleForLocation(location);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 1100;
    final narrowTopBar = screenWidth < 800;

    final drawer = _AppDrawer(role: role, profile: auth.profile);
    if (wide) {
      return Scaffold(
        drawer: drawer,
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1400,
              selectedIndex: _selectedIndex(items, location),
              onDestinationSelected: (index) => context.go(items[index].path),
              backgroundColor: dark ? AppColors.darkSurface : AppColors.plum800,
              indicatorColor: (dark ? AppColors.darkGold : AppColors.gold500)
                  .withOpacity(0.22),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: (dark ? AppColors.darkGold : AppColors.gold500)
                      .withOpacity(0.35),
                ),
              ),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (dark ? AppColors.darkBase : AppColors.plum900)
                        .withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      const YusraLogo(variant: YusraLogoVariant.mark, size: 44),
                ),
              ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(
                      item.icon,
                      color: dark ? AppColors.darkGold : AppColors.gold300,
                    ),
                    label: Text(
                      item.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: (dark ? AppColors.darkGold : AppColors.gold500)
                  .withOpacity(0.35),
            ),
            Expanded(
              child: Column(
                children: [
                  TopBar(title: title, narrow: narrowTopBar),
                  const Divider(height: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final bottom = bottomNavItems(role);
    final selectedBottom = _selectedIndex(bottom, location);
    return Scaffold(
      appBar: TopBar(title: title, narrow: narrowTopBar),
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: dark ? AppColors.darkSurface : AppColors.plum800,
            border: Border(
              top: BorderSide(
                color: (dark ? AppColors.darkGold : AppColors.gold500)
                    .withOpacity(0.35),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < bottom.length; i++)
                  _BottomNavItem(
                    item: bottom[i],
                    selected: i == selectedBottom,
                    dark: dark,
                    onTap: () => context.go(bottom[i].path),
                  ),
              ],
            ),
          ),
        ),
      ),
      drawer: drawer,
    );
  }

  int _selectedIndex(List<MenuItem> items, String location) {
    var best = 0;
    for (var i = 0; i < items.length; i++) {
      if (location == items[i].path ||
          location.startsWith('${items[i].path}/')) {
        best = i;
      }
    }
    return best;
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.role, required this.profile});
  final AppRole role;
  final UserProfile? profile;

  bool _can(String module) => can(role, module, PermAction.view);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final location = GoRouterState.of(context).uri.path;
    final name = profile?.fullName.trim();
    final displayName =
        (name == null || name.isEmpty) ? (profile?.email ?? 'User') : name;
    final roleLabel = profile?.role.label ?? role.label;

    Widget header() => DrawerHeader(
          decoration: BoxDecoration(
            color: dark ? AppColors.darkSurface : AppColors.plum800,
            border: Border(
                bottom: BorderSide(color: AppColors.gold500.withOpacity(0.35))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YusraLogo(
                  variant: YusraLogoVariant.mark, size: 52, onDark: true),
              const SizedBox(height: 12),
              Text(displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.onDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              const SizedBox(height: 2),
              Text(roleLabel,
                  style: const TextStyle(
                      color: AppColors.onDarkMuted, fontSize: 13)),
            ],
          ),
        );

    ListTile item(String label, IconData icon, String path,
        {bool visible = true, VoidCallback? onTap}) {
      if (!visible)
        return const ListTile(
            visualDensity: VisualDensity(horizontal: 0, vertical: -4),
            dense: true,
            minVerticalPadding: 0,
            contentPadding: EdgeInsets.zero,
            title: SizedBox.shrink());
      final selected = location == path || location.startsWith('$path/');
      return ListTile(
        leading: Icon(icon,
            color: selected ? AppColors.gold300 : AppColors.onDarkMuted),
        title: Text(label,
            style: TextStyle(
                color: selected ? AppColors.gold300 : AppColors.onDark,
                fontWeight: FontWeight.w600)),
        selected: selected,
        selectedTileColor: AppColors.gold500.withOpacity(0.12),
        onTap: onTap ??
            () {
              Navigator.pop(context);
              context.go(path);
            },
      );
    }

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.onDarkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        );

    final isAdmin = role == AppRole.admin || role == AppRole.superAdmin;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            header(),
            section('Main'),
            item('Dashboard', Icons.dashboard_outlined, '/dashboard',
                visible: _can(Modules.dashboard)),
            item('New sale', Icons.point_of_sale, '/pos',
                visible: _can(Modules.pos)),
            item('Drug status', Icons.monitor_heart_outlined,
                '/inventory/drug-status',
                visible: _can(Modules.stock)),
            item('Inventory', Icons.inventory_2_outlined, '/inventory',
                visible: _can(Modules.medicines) || _can(Modules.stock)),
            item('Purchasing', Icons.shopping_cart_outlined,
                '/purchasing/orders',
                visible: _can(Modules.purchaseOrders)),
            item('Activity log', Icons.history, '/activity',
                visible: _can(Modules.audit)),
            section('Money'),
            item('Expenses', Icons.account_balance_wallet_outlined, '/expenses',
                visible: _can(Modules.expenses)),
            item(
                'Add expense', Icons.add_circle_outline, '/expenses?action=add',
                visible: can(role, Modules.expenses, PermAction.edit)),
            item('Pharmacy value', Icons.account_balance_wallet_outlined,
                '/dashboard/pharmacy-value',
                visible: _can(Modules.reports) || isAdmin),
            item('Expected expenses and overdue', Icons.payments_outlined,
                '/dashboard/expected-expenses',
                visible: isAdmin),
            section('Team'),
            item('Staff list and status', Icons.groups_outlined, '/admin/users',
                visible: _can(Modules.users)),
            item('Add staff', Icons.person_add_alt_1_outlined,
                '/admin/users?action=add',
                visible: can(role, Modules.users, PermAction.edit)),
            item('My profile', Icons.person_outline, '/profile', visible: true),
            section('Settings'),
            item('Change password', Icons.lock_outline,
                '/profile/change-password',
                visible: true),
            item('Theme', Icons.brightness_6_outlined, '/settings/theme',
                visible: true),
            item('Branches', Icons.account_balance_outlined, '/admin/branches',
                visible: isAdmin && _can(Modules.branches)),
            item('Sign out', Icons.logout, '/login', visible: true, onTap: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).signOut();
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopBar({super.key, required this.title, this.narrow = false});

  final String title;
  final bool narrow;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile;
    final isSuperAdmin = profile?.role == AppRole.superAdmin;

    final actions = <Widget>[
      if (isSuperAdmin) _BranchSwitcher(compact: narrow),
      const _NotificationBell(),
      PopupMenuButton<String>(
        tooltip: profile?.fullName ?? S.profile,
        onSelected: (value) {
          if (value == 'profile') context.go('/profile');
          if (value == 'signout') ref.read(authProvider.notifier).signOut();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'profile', child: Text(S.profile)),
          PopupMenuItem(value: 'signout', child: Text(S.signOut)),
        ],
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: narrow ? 4 : 8, vertical: 8),
          child: CircleAvatar(
            radius: narrow ? 16 : 18,
            backgroundColor: AppColors.gold500.withOpacity(0.22),
            foregroundColor: AppColors.gold300,
            child: profile == null
                ? Icon(Icons.person, size: narrow ? 16 : 18)
                : Text(
                    profile.fullName.isEmpty
                        ? '?'
                        : profile.fullName[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: narrow ? 12 : 14,
                        fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ),
    ];

    return AppBar(
      toolbarHeight: 64,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        tooltip: 'Menu',
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
      titleSpacing: 8,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        ...actions,
        SizedBox(width: narrow ? 4 : 8),
      ],
    );
  }
}

class _BranchSwitcher extends ConsumerStatefulWidget {
  const _BranchSwitcher({this.compact = false});
  final bool compact;

  @override
  ConsumerState<_BranchSwitcher> createState() => _BranchSwitcherState();
}

class _BranchSwitcherState extends ConsumerState<_BranchSwitcher> {
  late Future<List<Map<String, dynamic>>> _branches;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(selectedBranchProvider);
    _branches = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!SupabaseService.isReady) return <Map<String, dynamic>>[];
    final rows = await SupabaseService.client
        .from('branches')
        .select()
        .eq('is_active', true)
        .order('name');
    final branches = List<Map<String, dynamic>>.from(rows as List);

    // A super admin (especially one created directly in Supabase) has no
    // branch_id. Default them to their own branch, or to the first active
    // branch, so stock, sales and every other create flow work immediately.
    final fallback = initialBranchId(
      branches,
      ownBranchId: ref.read(authProvider).profile?.branchId,
      touched: ref.read(branchSelectionSetProvider),
      selected: _selected,
    );
    if (fallback != null) {
      _selected = fallback;
      ref.read(selectedBranchProvider.notifier).state = fallback;
    }
    return branches;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _branches,
      builder: (context, snapshot) {
        final branches = snapshot.data ?? const <Map<String, dynamic>>[];
        if (branches.isEmpty) {
          return TextButton.icon(
            icon: const Icon(Icons.add_business_outlined, size: 18),
            label: const Text(S.addBranch),
            style: TextButton.styleFrom(foregroundColor: AppColors.gold300),
            onPressed: () => context.go('/admin/branches'),
          );
        }
        // A max width (not a fixed width) keeps the switcher usable when the
        // top bar wraps into several rows on a phone.
        final compact = widget.compact;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 120 : 180),
          child: DropdownButton<String?>(
            value: _selected,
            isExpanded: true,
            dropdownColor: AppColors.plum900,
            iconEnabledColor: AppColors.gold300,
            iconSize: compact ? 18 : 24,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              color: AppColors.onDark,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 13,
            ),
            hint: const Text(
              S.allBranchesViewOnly,
              style: TextStyle(color: AppColors.onDarkMuted),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(S.allBranchesViewOnly),
              ),
              for (final branch in branches)
                DropdownMenuItem<String?>(
                  value: branch['id'] as String?,
                  child: Text((branch['name'] as String?) ?? '—'),
                ),
              const DropdownMenuItem<String?>(
                value: _manageBranchesValue,
                child: Text(S.manageBranches),
              ),
            ],
            onChanged: (value) {
              if (value == _manageBranchesValue) {
                context.go('/admin/branches');
                return;
              }
              setState(() => _selected = value);
              ref.read(selectedBranchProvider.notifier).state = value;
              ref.read(branchSelectionSetProvider.notifier).state = true;
            },
          ),
        );
      },
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  Future<int> _count() async {
    if (!SupabaseService.isReady) return 0;
    final client = SupabaseService.client;
    final low = await client.from('v_low_stock').select();
    final expiring = await client.from('v_expiring_batches').select();
    return (low as List).length + (expiring as List).length;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final isAdmin = role == AppRole.superAdmin || role == AppRole.admin;
    if (isAdmin) {
      final count = ref.watch(lowStockAlertCountProvider);
      return IconButton(
        tooltip: S.alerts,
        onPressed: () => context.go('/dashboard'),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.notifications_none_outlined),
        ),
      );
    }
    return FutureBuilder<int>(
      future: _count(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return IconButton(
          tooltip: S.alerts,
          onPressed: () => context.go('/inventory/alerts'),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: const Icon(Icons.notifications_none_outlined),
          ),
        );
      },
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.item,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  final MenuItem item;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? (dark ? AppColors.darkGold : AppColors.gold300)
        : (dark ? AppColors.darkMuted : AppColors.onDarkMuted);
    final bg = selected
        ? (dark ? AppColors.darkGold : AppColors.gold500).withOpacity(0.18)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? (dark ? AppColors.darkGold : AppColors.gold500)
                      .withOpacity(0.35)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
