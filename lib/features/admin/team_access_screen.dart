import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/state/app_cache.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';
import '../auth/forbidden_screen.dart';
import '../sales/data/sales.dart';

/// Super-admin team access sharing.
///
/// All mutations go through the proposed RPCs in 0015_team_management.sql:
/// the app never writes profiles or auth.users directly. Selecting teammates
/// and sharing access copies the caller's role/branch; publishing settings
/// re-writes the global app_settings rows and records an audit entry.
class TeamAccessScreen extends ConsumerStatefulWidget {
  const TeamAccessScreen({super.key});

  @override
  ConsumerState<TeamAccessScreen> createState() => _TeamAccessScreenState();
}

class _TeamAccessScreenState extends ConsumerState<TeamAccessScreen> {
  List<Map<String, dynamic>> _members = const [];
  List<Map<String, dynamic>> _branches = const [];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _canEdit => can(
        ref.read(authProvider).profile?.role ?? AppRole.cashier,
        Modules.teamAccess,
        PermAction.edit,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final client = SupabaseService.client;
      final members = await client
          .from('profiles')
          .select('id, full_name, email, role, branch_id, is_active')
          .order('full_name');
      final branches =
          await client.from('branches').select('id, name').order('name');
      setState(() {
        _members = List<Map<String, dynamic>>.from(members as List);
        _branches = List<Map<String, dynamic>>.from(branches as List);
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _afterMutation() async {
    await ref.read(authProvider.notifier).refreshProfile();
    ref.invalidate(receiptSettingsProvider);
    ref.invalidateCache(CacheTag.users);
    ref.invalidateCache(CacheTag.settings);
  }

  Future<void> _shareAccess() async {
    if (_selected.isEmpty) {
      AppSnackbar.show(context, S.selectTeammates, kind: SnackKind.info);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.shareAccess),
        content: Text(
          '${S.selectTeammates}: ${_selected.length}.\n${S.teamAccessBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.shareAccess),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.rpc(
        'share_admin_access',
        params: {'p_targets': _selected.toList()},
      );
      await _afterMutation();
      if (mounted) AppSnackbar.success(context, S.teamShareDone);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.publishSettings),
        content: const Text(S.teamAccessBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.publishSettings),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.rpc('publish_app_settings');
      await _afterMutation();
      if (mounted) AppSnackbar.success(context, S.settingsPublished);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAccess(Map<String, dynamic> member) async {
    final result = await showDialog<_AccessInput>(
      context: context,
      builder: (_) => _AccessDialog(member: member, branches: _branches),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.rpc('set_user_access', params: {
        'p_user': member['id'],
        'p_role': result.role.dbName,
        'p_branch': result.branchId,
        'p_active': result.active,
      });
      await _afterMutation();
      if (mounted) AppSnackbar.success(context, S.accessUpdated);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _branchName(String? id) => _branches
      .where((b) => b['id'] == id)
      .map((b) => (b['name'] as String?) ?? '—')
      .firstWhere((_) => true, orElse: () => '—');

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.teamAccess, PermAction.view)) {
      return const ForbiddenScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text(S.teamAccess)),
      body: _loading
          ? const LoadingSkeleton(lines: 6)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.teamAccessBody,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _busy || !_canEdit
                                    ? null
                                    : _publishSettings,
                                icon: const Icon(Icons.public),
                                label: const Text(S.publishSettings),
                              ),
                              ElevatedButton.icon(
                                onPressed:
                                    _busy || !_canEdit || _selected.isEmpty
                                        ? null
                                        : _shareAccess,
                                icon: const Icon(Icons.group_add_outlined),
                                label: Text(
                                  '${S.shareAccess} (${_selected.length})',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    ErrorState(message: _error!, onRetry: _load),
                  ],
                  const SizedBox(height: 12),
                  if (_members.isEmpty)
                    const EmptyState(message: S.noTeamMembers)
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final member in _members)
                            ListTile(
                              leading: Checkbox(
                                value: _selected.contains(member['id']),
                                onChanged: _canEdit
                                    ? (value) => setState(() {
                                          if (value == true) {
                                            _selected
                                                .add(member['id'] as String);
                                          } else {
                                            _selected.remove(member['id']);
                                          }
                                        })
                                    : null,
                              ),
                              title: Text(
                                (member['full_name'] as String?)?.isEmpty ??
                                        true
                                    ? (member['email'] as String?) ?? '—'
                                    : member['full_name'] as String,
                              ),
                              subtitle: Text(
                                '${AppRoleX.fromDb(member['role'] as String?)?.label ?? member['role']}'
                                ' · ${_branchName(member['branch_id'] as String?)}'
                                ' · ${member['is_active'] == true ? S.active : S.inactive}',
                              ),
                              trailing: _canEdit
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.manage_accounts_outlined),
                                      tooltip: S.editAccess,
                                      onPressed: _busy
                                          ? null
                                          : () => _editAccess(member),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _AccessInput {
  const _AccessInput({
    required this.role,
    required this.branchId,
    required this.active,
  });

  final AppRole role;
  final String? branchId;
  final bool active;
}

class _AccessDialog extends StatefulWidget {
  const _AccessDialog({required this.member, required this.branches});

  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> branches;

  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog> {
  late AppRole _role;
  String? _branchId;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _role =
        AppRoleX.fromDb(widget.member['role'] as String?) ?? AppRole.cashier;
    _branchId = widget.member['branch_id'] as String?;
    _active = widget.member['is_active'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(S.editAccess),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AppRole>(
              value: _role,
              decoration: const InputDecoration(labelText: S.role),
              items: [
                for (final role in AppRole.values)
                  DropdownMenuItem(value: role, child: Text(role.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _branchId,
              decoration: const InputDecoration(labelText: S.branch),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All branches')),
                for (final branch in widget.branches)
                  DropdownMenuItem<String?>(
                    value: branch['id'] as String?,
                    child: Text((branch['name'] as String?) ?? '—'),
                  ),
              ],
              onChanged: (value) => setState(() => _branchId = value),
            ),
            SwitchListTile(
              title: const Text(S.active),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            _AccessInput(role: _role, branchId: _branchId, active: _active),
          ),
          child: const Text(S.save),
        ),
      ],
    );
  }
}
