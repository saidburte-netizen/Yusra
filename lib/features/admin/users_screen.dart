import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/state/app_cache.dart';
import '../../core/state/invalidation.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({
    super.key,
    this.initialUsers,
    this.initialBranches,
    this.initialError,
  });

  /// Optional preloaded data keeps this screen pumpable in widget tests without
  /// standing up a Supabase client. Production routes use the plain constructor.
  final List<Map<String, dynamic>>? initialUsers;
  final List<Map<String, dynamic>>? initialBranches;
  final String? initialError;

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
  bool _handledAction = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsers != null || widget.initialError != null) {
      _users = widget.initialUsers ?? const [];
      _branches = widget.initialBranches ?? const [];
      _error = widget.initialError;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledAction) return;
    final action = GoRouterState.of(context).uri.queryParameters['action'];
    if (action == 'add') {
      _handledAction = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createUser();
      });
    }
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

  List<AppRole> get _allowedRoles {
    final actor = ref.read(authProvider).profile?.role;
    if (actor == AppRole.superAdmin) return AppRole.values;
    return AppRole.values.where((role) => role != AppRole.superAdmin).toList();
  }

  List<Map<String, dynamic>> get _filtered => _users.where((row) {
        if (_roleFilter != null && row['role'] != _roleFilter) return false;
        if (_statusFilter != null &&
            row['is_active'] != (_statusFilter == S.active)) {
          return false;
        }
        if (_branchFilter != null && row['branch_id'] != _branchFilter) {
          return false;
        }
        return true;
      }).toList();

  String _branchName(String? id) => _branches
      .where((b) => b['id'] == id)
      .map((b) => (b['name'] as String?) ?? '—')
      .firstWhere((_) => true, orElse: () => '—');

  void _viewUser(Map<String, dynamic> user) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text((user['full_name'] as String?) ?? '—'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((user['email'] as String?) ?? '—'),
              const SizedBox(height: 8),
              Text(AppRoleX.fromDb(user['role'] as String?)?.label ?? '—'),
              const SizedBox(height: 8),
              Text(_branchName(user['branch_id'] as String?)),
              const SizedBox(height: 8),
              Text(user['is_active'] == true ? S.active : S.inactive),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Mirrors the checks made by set_user_access / admin-reset-password so a
  /// button that the database would reject is never shown in the first place.
  bool _canManage(Map<String, dynamic> user) {
    final profile = ref.read(authProvider).profile;
    if (profile == null) return false;
    final actor = profile.role;
    if (!can(actor, Modules.users, PermAction.edit)) return false;
    final target = AppRoleX.fromDb(user['role'] as String?) ?? AppRole.cashier;
    if (!canManageUser(actor, target)) return false;
    // The RPC refuses self edits, and admins are scoped to their own branch.
    if (user['id'] == profile.id) return false;
    if (actor != AppRole.superAdmin &&
        (profile.branchId == null || user['branch_id'] != profile.branchId)) {
      return false;
    }
    return true;
  }

  bool _canDeactivate(Map<String, dynamic> user) {
    if (!_canManage(user)) return false;
    // set_user_access refuses to deactivate a super admin.
    return AppRoleX.fromDb(user['role'] as String?) != AppRole.superAdmin;
  }

  /// Shows the real server reason with a copyable diagnostic block. The
  /// "not deployed" hint is reserved for the exact missing-function body so a
  /// 404 caused by a bad staff profile is never hidden.
  void _showCreateUserError(Object error) {
    final failure = _describeFunctionFailure(error, 'admin-create-user');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create user failed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failure.message),
              const SizedBox(height: 12),
              const Text('Details:'),
              const SizedBox(height: 4),
              SelectableText(
                failure.details,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy details'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: failure.details));
              if (context.mounted) {
                AppSnackbar.success(context, 'Details copied.');
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  /// Keeps the signed-in user's own permissions fresh and drops cached users.
  Future<void> _afterUserMutation(Object? userId) async {
    if (userId != null && userId == ref.read(authProvider).profile?.id) {
      await ref.read(authProvider.notifier).refreshProfile();
    }
    ref.invalidateCache(CacheTag.users);
  }

  Future<void> _createUser() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(
        allowedRoles: _allowedRoles,
        branches: _branches,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      // The Edge Function generates the temporary password and accepts only
      // these keys. Never send a client-generated password or unknown fields.
      final salaryText = (result['monthly_salary'] ?? '').toString().trim();
      final salary = salaryText.isEmpty ? null : num.tryParse(salaryText);
      final hiringDate = (result['hiring_date'] ?? '').toString();
      final body = <String, dynamic>{
        'email': result['email'],
        'full_name': result['full_name'],
        'role': result['role'],
        'branch_id': result['branch_id'],
        'phone': (result['phone'] ?? '').toString().trim().isEmpty
            ? null
            : result['phone'],
        'monthly_salary': salary,
        'hiring_date': hiringDate.isEmpty ? null : hiringDate.split('T').first,
      };
      final response = await SupabaseService.client.functions.invoke(
        'admin-create-user',
        body: body,
      );
      final data = _decodeEdgeResponse(response.data);
      final tempPassword = data is Map
          ? (data['temporary_password'] ?? data['temporaryPassword'])
              ?.toString()
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
                const SizedBox(height: 8),
                const Text(
                  'The staff member must change this password at first login.',
                ),
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
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: tempPassword));
                  if (context.mounted) {
                    AppSnackbar.success(context, 'Password copied.');
                  }
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(S.close),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      ref.applyMutation(Mutation.saveUser);
      AppSnackbar.success(context, 'Staff member created.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showCreateUserError(e);
    }
  }

  Future<String?> _editUser(Map<String, dynamic> user) async {
    if (!_canManage(user)) throw AppError(S.forbidden, kind: AppErrorKind.permission);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(
        allowedRoles: _allowedRoles,
        branches: _branches,
        initialRole: user['role'] as String?,
        initialBranch: user['branch_id'] as String?,
        initialName: user['full_name'] as String?,
        initialEmail: user['email'] as String?,
        isEdit: true,
      ),
    );
    if (result == null) return null;
    final salaryText = (result['monthly_salary'] ?? '').toString().trim();
    final salary = salaryText.isEmpty ? null : num.tryParse(salaryText);
    final hiringDate = (result['hiring_date'] ?? '').toString();
    // One RPC updates every staff field; the profiles audit trigger records it.
    await SupabaseService.client.rpc('update_staff_profile', params: {
      'p_user': user['id'],
      'p_full_name': result['full_name'],
      'p_phone': (result['phone'] ?? '').toString().trim().isEmpty
          ? null
          : result['phone'],
      'p_role': result['role'],
      'p_branch': result['branch_id'],
      'p_monthly_salary': salary,
      'p_hiring_date': hiringDate.isEmpty ? null : hiringDate.split('T').first,
    });
    await _afterUserMutation(user['id']);
    await _load();
    return 'Staff details updated.';
  }

  Future<String?> _setActive(Map<String, dynamic> user, bool active) async {
    if (!_canDeactivate(user)) {
      throw AppError(S.forbidden, kind: AppErrorKind.permission);
    }
    await SupabaseService.client.rpc('set_user_access', params: {
      'p_user': user['id'],
      'p_role': user['role'],
      'p_branch': user['branch_id'],
      'p_active': active,
    });
    await _afterUserMutation(user['id']);
    await _load();
    return active ? 'User reactivated.' : 'User deactivated.';
  }

  Future<String?> _resetPassword(Map<String, dynamic> user) async {
    if (!_canManage(user)) {
      throw AppError(S.forbidden, kind: AppErrorKind.permission);
    }
    {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final response = await SupabaseService.client.functions.invoke(
        'admin-reset-password',
        body: {'user_id': user['id']},
      );
      final data = _decodeEdgeResponse(response.data);
      final temp = data is Map ? data['temporary_password']?.toString() : null;
      if (!mounted) return null;
      if (temp != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(S.temporaryPassword),
            content: SelectableText(temp),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(S.close)),
            ],
          ),
        );
      }
      return 'Password reset.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.users, PermAction.edit);
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
                              const DropdownMenuItem(
                                  value: null, child: Text(S.all)),
                              for (final r in AppRole.values)
                                DropdownMenuItem(
                                    value: r.dbName, child: Text(r.label)),
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
                              DropdownMenuItem(
                                  value: S.active, child: Text(S.active)),
                              DropdownMenuItem(
                                  value: S.inactive, child: Text(S.inactive)),
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
                              const DropdownMenuItem(
                                  value: null, child: Text(S.all)),
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
                    if (_users.isEmpty)
                      const EmptyState(
                        message: 'No users found.',
                        icon: Icons.people_outline,
                      )
                    else
                      Expanded(
                        child: SingleChildScrollView(
                          child: DataTablePlus(
                            columns: const [
                              S.fullName,
                              S.email,
                              S.role,
                              S.branch,
                              S.status,
                            ],
                            rows: [
                              for (final user in _filtered)
                                DataTablePlusRow(
                                  cells: [
                                    (user['full_name'] as String?) ?? '—',
                                    (user['email'] as String?) ?? '—',
                                    AppRoleX.fromDb(user['role'] as String?)
                                            ?.label ??
                                        '—',
                                    _branchName(user['branch_id'] as String?),
                                    user['is_active'] == true
                                        ? S.active
                                        : S.inactive,
                                  ],
                                  // No hard delete: deactivation is the books-safe
                                  // replacement and keeps sales/audit history intact.
                                  actions: [
                                    RowActions(actions: [
                                      RowAction(
                                        label: S.view,
                                        icon: Icons.visibility_outlined,
                                        onSelected: () async {
                                          _viewUser(user);
                                          return null;
                                        },
                                      ),
                                      RowAction(
                                        label: S.edit,
                                        icon: Icons.edit_outlined,
                                        allowed: canEdit && _canManage(user),
                                        onSelected: () => _editUser(user),
                                        successMessage: 'Staff details updated.',
                                        mutation: Mutation.saveUser,
                                      ),
                                      RowAction(
                                        label: S.resetPassword,
                                        icon: Icons.lock_reset_outlined,
                                        allowed: canEdit && _canManage(user),
                                        confirmTitle: S.resetPassword,
                                        confirmMessage:
                                            'Send a new temporary password to ${user['email'] ?? 'this user'}?',
                                        danger: false,
                                        onSelected: () => _resetPassword(user),
                                      ),
                                      RowAction(
                                        label: user['is_active'] == true
                                            ? S.deactivate
                                            : S.reactivate,
                                        icon: user['is_active'] == true
                                            ? Icons.person_off_outlined
                                            : Icons.person_outline,
                                        allowed: canEdit && _canDeactivate(user),
                                        confirmTitle: user['is_active'] == true
                                            ? S.deactivate
                                            : S.reactivate,
                                        confirmMessage:
                                            '${user['is_active'] == true ? S.deactivate : S.reactivate} ${user['full_name'] ?? ''}?',
                                        onSelected: () => _setActive(
                                            user, user['is_active'] != true),
                                        mutation: Mutation.saveUser,
                                      ),
                                    ]),
                                  ],
                                ),
                            ],
                          ),
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

class _FunctionFailure {
  const _FunctionFailure({required this.message, required this.details});

  final String message;
  final String details;
}

class _FunctionBodyInfo {
  const _FunctionBodyInfo({this.message, this.code, required this.raw});

  final String? message;
  final String? code;
  final String raw;
}

/// Describes an invoke failure from the server body, not from exception text.
/// A 404 only means "not deployed" when the body itself says the function was
/// missing; every other 404 keeps its real message and HTTP status.
_FunctionFailure _describeFunctionFailure(Object error, String functionName) {
  final action = functionName == 'admin-create-user'
      ? 'Create user failed'
      : 'Staff request failed';
  final mapped = AppErrorMapper.from(error);
  if (error is! FunctionException) {
    return _FunctionFailure(
      message: '$action: ${mapped.message}',
      details: <String>[
        'Function: $functionName',
        'Message: ${mapped.message}',
        if (mapped.code != null) 'Error code: ${mapped.code}',
      ].join('\n'),
    );
  }

  final body = _functionBodyInfo(error.details);
  final serverMessage = body.message?.trim();
  final hasMessage = serverMessage != null && serverMessage.isNotEmpty;
  final message = hasMessage ? serverMessage : mapped.message;
  final missingFunction = error.status == 404 &&
      hasMessage &&
      serverMessage.toLowerCase().contains('requested function was not found');
  final code = _shortFunctionCode(body.code);
  final headline = '$action (${error.status}): $message';
  final displayMessage = missingFunction
      ? 'Staff service is not deployed yet. Ask the owner to run Deploy '
          'functions in GitHub Actions.'
      : code == null
          ? headline
          : '$headline\nError code: $code';
  return _FunctionFailure(
    message: displayMessage,
    details: <String>[
      'Function: $functionName',
      'HTTP status: ${error.status}',
      if (error.reasonPhrase != null) 'Reason: ${error.reasonPhrase}',
      'Message: $message',
      if (code != null) 'Error code: $code',
      'Body: ${body.raw}',
    ].join('\n'),
  );
}

_FunctionBodyInfo _functionBodyInfo(Object? details) {
  if (details == null) return const _FunctionBodyInfo(raw: '<empty>');
  if (details is! String) return _functionBodyInfoFromValue(details);

  final text = details.trim();
  try {
    return _functionBodyInfoFromValue(jsonDecode(text));
  } on FormatException {
    return _FunctionBodyInfo(message: text, raw: text);
  }
}

_FunctionBodyInfo _functionBodyInfoFromValue(Object? decoded) {
  if (decoded is Map) {
    final nested = decoded['error'];
    final errorMap = nested is Map ? nested : null;
    final message = errorMap?['message']?.toString() ??
        decoded['message']?.toString() ??
        decoded['error_description']?.toString() ??
        (nested is String ? nested : null);
    final code = errorMap?['code']?.toString() ??
        decoded['code']?.toString() ??
        decoded['error_code']?.toString();
    var raw = '<empty>';
    try {
      raw = jsonEncode(decoded);
    } on Object {
      raw = decoded.toString();
    }
    return _FunctionBodyInfo(message: message, code: code, raw: raw);
  }
  final text = decoded?.toString() ?? '<empty>';
  return _FunctionBodyInfo(message: text, raw: text);
}

String? _shortFunctionCode(Object? raw) {
  final code = raw?.toString().trim();
  if (code == null || code.isEmpty || code.length > 64) return null;
  if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(code)) return null;
  return code;
}

/// Edge Functions return typed `{error:{code,message}}` bodies. Decode both
/// raw JSON strings and already-decoded maps, and turn typed errors into a
/// mapped AppError so no raw function exception reaches the UI.
Object _decodeEdgeResponse(Object? raw) {
  final data = raw is String ? jsonDecode(raw) : raw;
  if (data is Map && data['error'] is Map) {
    final error = data['error'] as Map;
    throw AppError(
      error['message']?.toString() ?? S.somethingWrong,
      kind: AppErrorKind.server,
      code: error['code']?.toString(),
    );
  }
  return data ?? const <String, dynamic>{};
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.allowedRoles,
    required this.branches,
    this.initialRole,
    this.initialBranch,
    this.initialName,
    this.initialEmail,
    this.isEdit = false,
  });

  final List<AppRole> allowedRoles;
  final List<Map<String, dynamic>> branches;
  final String? initialRole;
  final String? initialBranch;
  final String? initialName;
  final String? initialEmail;
  final bool isEdit;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _salary;
  DateTime? _hiringDate;
  String? _role;
  String? _branch;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
    _name = TextEditingController(text: widget.initialName ?? '');
    _phone = TextEditingController();
    _salary = TextEditingController();
    _hiringDate = null;
    _role = widget.initialRole;
    _branch = widget.initialBranch;
    if (_role != null &&
        !widget.allowedRoles.any((role) => role.dbName == _role)) {
      _role = null;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? S.edit : 'Add staff'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: S.fullName,
                  controller: _name,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? S.required : null,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Phone',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                AppDropdown<String>(
                  label: S.role,
                  value: _role,
                  items: [
                    for (final r in widget.allowedRoles)
                      DropdownMenuItem(value: r.dbName, child: Text(r.label)),
                  ],
                  onChanged: (v) => setState(() => _role = v),
                  validator: (v) => v == null ? S.required : null,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Monthly salary',
                  controller: _salary,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _hiringDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _hiringDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hiring date',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _hiringDate == null
                          ? 'Select date'
                          : '${_hiringDate!.year}-${_hiringDate!.month.toString().padLeft(2, '0')}-${_hiringDate!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppDropdown<String>(
                  label: S.branch,
                  value: _branch,
                  items: [
                    for (final b in widget.branches)
                      DropdownMenuItem(
                        value: b['id'] as String?,
                        child: Text((b['name'] as String?) ?? '—'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _branch = v),
                ),
                if (!widget.isEdit) ...[
                  const SizedBox(height: 12),
                  AppTextField(
                    label: S.email,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v == null || !v.contains('@') ? S.emailInvalid : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(S.cancel)),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, <String, dynamic>{
              'email': _email.text.trim(),
              'full_name': _name.text.trim(),
              'phone': _phone.text.trim(),
              'role': _role,
              'branch_id': _branch,
              'monthly_salary': _salary.text.trim(),
              'hiring_date': _hiringDate?.toIso8601String(),
            });
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}
