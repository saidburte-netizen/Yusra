import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/state/app_cache.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;
  String? _error;
  String? _roleFilter;
  String? _statusFilter;
  String? _branchFilter;

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
      final users = await client.from('profiles').select().order('full_name');
      final branches = await client.from('branches').select().order('name');
      setState(() {
        _users = List<Map<String, dynamic>>.from(users as List);
        _branches = List<Map<String, dynamic>>.from(branches as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered => _users.where((row) {
        if (_roleFilter != null && row['role'] != _roleFilter) return false;
        if (_statusFilter != null && row['is_active'] != (_statusFilter == S.active)) {
          return false;
        }
        if (_branchFilter != null && row['branch_id'] != _branchFilter) return false;
        return true;
      }).toList();

  String _branchName(String? id) => _branches
      .where((b) => b['id'] == id)
      .map((b) => (b['name'] as String?) ?? '—')
      .firstWhere((_) => true, orElse: () => '—');

  /// Keeps the signed-in user's own permissions fresh and drops cached users.
  void _afterUserMutation(Object? userId) {
    if (userId != null && userId == ref.read(authProvider).profile?.id) {
      ref.invalidate(authProvider);
    }
    ref.invalidateCache(CacheTag.users);
  }

  Future<void> _createUser() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _UserFormDialog(),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      final response = await SupabaseService.client.functions.invoke(
        'admin-create-user',
        body: result,
      );
      final rawData = response.data;
      final data = rawData is String ? jsonDecode(rawData) : rawData;
      final tempPassword = data is Map
          ? (data['temporary_password'] ?? data['temporaryPassword'])?.toString()
          : null;
      if (!mounted) return;
      setState(() => _loading = false);
      await _load();
      if (!mounted) return;
      if (tempPassword != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(S.temporaryPassword),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(S.copyOnce),
                const SizedBox(height: 12),
                SelectableText(
                  tempPassword,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(S.close),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      AppSnackbar.success(context, S.saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final actor = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    final target = AppRoleX.fromDb(user['role'] as String?) ?? AppRole.cashier;
    if (!canManageUser(actor, target)) {
      AppSnackbar.error(context, S.forbidden);
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(
        initialRole: user['role'] as String?,
        initialBranch: user['branch_id'] as String?,
        initialName: user['full_name'] as String?,
        showPasswordFields: false,
      ),
    );
    if (result == null) return;
    try {
      await SupabaseService.client
          .from('profiles')
          .update({
            'role': result['role'],
            'branch_id': result['branch_id'],
            'full_name': result['full_name'],
          })
          .eq('id', user['id']);
      if (!mounted) return;
      _afterUserMutation(user['id']);
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _setActive(Map<String, dynamic> user, bool active) async {
    final actor = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    final target = AppRoleX.fromDb(user['role'] as String?) ?? AppRole.cashier;
    if (!canManageUser(actor, target)) {
      AppSnackbar.error(context, S.forbidden);
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: active ? S.reactivate : S.deactivate,
      message: '${active ? S.reactivate : S.deactivate} ${user['full_name'] ?? ''}?',
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client
          .from('profiles')
          .update({'is_active': active})
          .eq('id', user['id']);
      if (!mounted) return;
      _afterUserMutation(user['id']);
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final confirm = await showConfirmDialog(
      context,
      title: S.resetPassword,
      message: 'Send a new temporary password to ${user['email'] ?? 'this user'}?',
      danger: false,
    );
    if (confirm != true) return;
    try {
      final response = await SupabaseService.client.functions.invoke(
        'admin-reset-password',
        body: {'user_id': user['id']},
      );
      final data = response.data;
      final temp = data is Map ? data['temporary_password']?.toString() : null;
      if (!mounted) return;
      if (temp != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(S.temporaryPassword),
            content: SelectableText(temp),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close)),
            ],
          ),
        );
      } else {
        AppSnackbar.success(context, S.saved);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role;
    final canEdit = role == AppRole.superAdmin || role == AppRole.admin;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.users,
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: S.createUser,
                      icon: Icons.person_add_outlined,
                      onPressed: _createUser,
                      width: 180,
                    ),
                  ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else
              Expanded(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 10,
                      children: [
                        SizedBox(
                          width: 180,
                          child: AppDropdown<String?>(
                            label: S.role,
                            value: _roleFilter,
                            items: [
                              const DropdownMenuItem(value: null, child: Text(S.all)),
                              for (final r in AppRole.values)
                                DropdownMenuItem(value: r.dbName, child: Text(r.label)),
                            ],
                            onChanged: (v) => setState(() => _roleFilter = v),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: AppDropdown<String?>(
                            label: S.status,
                            value: _statusFilter,
                            items: const [
                              DropdownMenuItem(value: null, child: Text(S.all)),
                              DropdownMenuItem(value: S.active, child: Text(S.active)),
                              DropdownMenuItem(value: S.inactive, child: Text(S.inactive)),
                            ],
                            onChanged: (v) => setState(() => _statusFilter = v),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: AppDropdown<String?>(
                            label: S.branch,
                            value: _branchFilter,
                            items: [
                              const DropdownMenuItem(value: null, child: Text(S.all)),
                              for (final b in _branches)
                                DropdownMenuItem(
                                  value: b['id'] as String?,
                                  child: Text((b['name'] as String?) ?? '—'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _branchFilter = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: DataTablePlus(
                        columns: const [
                          S.fullName, S.email, S.role, S.branch, S.status, S.actionLabel,
                        ],
                        rows: [
                          for (final user in _filtered)
                            DataTablePlusRow(
                              cells: [
                                (user['full_name'] as String?) ?? '—',
                                (user['email'] as String?) ?? '—',
                                AppRoleX.fromDb(user['role'] as String?)?.label ?? '—',
                                _branchName(user['branch_id'] as String?),
                                user['is_active'] == true ? S.active : S.inactive,
                              ],
                              actions: [
                                if (canEdit)
                                  IconButton(
                                    tooltip: S.edit,
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _editUser(user),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: S.resetPassword,
                                    icon: const Icon(Icons.lock_reset_outlined, size: 18),
                                    onPressed: () => _resetPassword(user),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: user['is_active'] == true
                                        ? S.deactivate
                                        : S.reactivate,
                                    icon: Icon(
                                      user['is_active'] == true
                                          ? Icons.person_off_outlined
                                          : Icons.person_outline,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        _setActive(user, user['is_active'] != true),
                                  ),
                              ],
                            ),
                        ],
                      ),
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

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    this.initialRole,
    this.initialBranch,
    this.initialName,
    this.showPasswordFields = true,
  });

  final String? initialRole;
  final String? initialBranch;
  final String? initialName;
  final bool showPasswordFields;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _name;
  String? _role;
  String? _branch;
  List<Map<String, dynamic>> _branches = const [];

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
    _name = TextEditingController(text: widget.initialName ?? '');
    _role = widget.initialRole;
    _branch = widget.initialBranch;
    if (SupabaseService.isReady) {
      SupabaseService.client.from('branches').select().order('name').then((rows) {
        if (mounted) setState(() => _branches = List<Map<String, dynamic>>.from(rows as List));
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.showPasswordFields ? S.createUser : S.edit),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showPasswordFields)
                AppTextField(
                  label: S.email,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v == null || !v.contains('@') ? S.emailInvalid : null,
                ),
              if (widget.showPasswordFields) const SizedBox(height: 12),
              AppTextField(
                label: S.fullName,
                controller: _name,
                validator: (v) => v == null || v.trim().isEmpty ? S.required : null,
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                label: S.role,
                value: _role,
                items: [
                  for (final r in AppRole.values)
                    DropdownMenuItem(value: r.dbName, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => _role = v),
                validator: (v) => v == null ? S.required : null,
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                label: S.branch,
                value: _branch,
                items: [
                  for (final b in _branches)
                    DropdownMenuItem(
                      value: b['id'] as String?,
                      child: Text((b['name'] as String?) ?? '—'),
                    ),
                ],
                onChanged: (v) => setState(() => _branch = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, <String, dynamic>{
              'email': _email.text.trim(),
              'full_name': _name.text.trim(),
              'role': _role,
              'branch_id': _branch,
            });
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}
