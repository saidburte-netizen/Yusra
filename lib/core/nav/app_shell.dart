import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../permissions.dart';
import '../strings.dart';
import '../supabase_client.dart';
import '../theme/app_colors.dart';
import '../widgets.dart';
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
    final auth = ref.watch(authProvider);
    final role = auth.profile?.role ?? AppRole.cashier;
    final items = menuFor(role);
    final location = GoRouterState.of(context).uri.path;
    final title = titleForLocation(location);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 1100;
    final narrowTopBar = screenWidth < 800;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1400,
              selectedIndex: _selectedIndex(items, location),
              onDestinationSelected: (index) => context.go(items[index].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: YusraLogo(variant: YusraLogoVariant.mark, size: 44),
              ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
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
    return Scaffold(
      appBar: TopBar(title: title, narrow: narrowTopBar),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(bottom, location),
        onDestinationSelected: (index) => context.go(bottom[index].path),
        destinations: [
          for (final item in bottom)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: YusraLogo(variant: YusraLogoVariant.full, size: 180),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in items)
                      ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        selected: location.startsWith(item.path),
                        onTap: () {
                          Navigator.pop(context);
                          context.go(item.path);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopBar({super.key, required this.title, this.narrow = false});

  final String title;

  /// Set by [AppShell] from MediaQuery. The parent decides it so [preferredSize]
  /// (read before this widget builds) always matches the rendered height.
  final bool narrow;

  @override
  Size get preferredSize => Size.fromHeight(narrow ? 132 : 64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile;
    final isSuperAdmin = profile?.role == AppRole.superAdmin;

    final actions = <Widget>[
      if (isSuperAdmin) const _BranchSwitcher(),
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
          padding: const EdgeInsets.all(8),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.pink50,
            foregroundColor: AppColors.pink600,
            child: profile == null
                ? const Icon(Icons.person, size: 18)
                : Text(
                    profile.fullName.isEmpty
                        ? '?'
                        : profile.fullName[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    ];

    if (narrow) {
      return AppBar(
        toolbarHeight: 132,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ),
      );
    }

    return AppBar(
      title: Text(title),
      actions: [
        ...actions,
        const SizedBox(width: 8),
      ],
    );
  }
}

class _BranchSwitcher extends ConsumerStatefulWidget {
  const _BranchSwitcher();

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
            onPressed: () => context.go('/admin/branches'),
          );
        }
        // A max width (not a fixed width) keeps the switcher usable when the
        // top bar wraps into several rows on a phone.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: DropdownButton<String?>(
            value: _selected,
            isExpanded: true,
            hint: const Text(S.allBranchesViewOnly),
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

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  Future<int> _count() async {
    if (!SupabaseService.isReady) return 0;
    final client = SupabaseService.client;
    final low = await client.from('v_low_stock').select();
    final expiring = await client.from('v_expiring_batches').select();
    return (low as List).length + (expiring as List).length;
  }

  @override
  Widget build(BuildContext context) {
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
