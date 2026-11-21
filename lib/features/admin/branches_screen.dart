import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/nav/app_shell.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/state/app_cache.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

/// Pharmacy branches. Only a super_admin may edit; admins get a read-only view
/// (see the permission matrix).
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({
    super.key,
    this.initialBranches,
    this.initialError,
  });

  /// Optional preloaded data keeps this screen pumpable in widget tests.
  final List<Map<String, dynamic>>? initialBranches;
  final String? initialError;

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    if (widget.initialBranches != null || widget.initialError != null) {
      _branches = widget.initialBranches ?? const [];
      _error = widget.initialError;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final rows =
          await SupabaseService.client.from('branches').select().order('name');
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  /// Selecting another branch changes the scope of nearly every list in the
  /// app, so both Riverpod providers and the TTL cache must be refreshed.
  void _invalidateBranchData() {
    ref.invalidateCaches(const [
      CacheTag.catalogue,
      CacheTag.stock,
      CacheTag.sales,
      CacheTag.shifts,
      CacheTag.purchases,
      CacheTag.prescriptions,
      CacheTag.expenses,
      CacheTag.reports,
      CacheTag.users,
    ]);
  }

  List<Map<String, dynamic>> get _filtered => _branches.where((row) {
        if (_statusFilter == null) return true;
        return row['is_active'] == (_statusFilter == S.active);
      }).toList();

  Future<void> _edit(Map<String, dynamic>? branch) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BranchFormDialog(initial: branch),
    );
    if (result == null) return;
    try {
      final client = SupabaseService.client;
      if (branch == null) {
        final inserted =
            await client.from('branches').insert(result).select().single();
        // Make the first branch immediately usable for create flows.
        if (ref.read(selectedBranchProvider) == null) {
          final id = inserted['id'] as String?;
          if (id != null) {
            ref.read(selectedBranchProvider.notifier).state = id;
            ref.read(branchSelectionSetProvider.notifier).state = true;
          }
        }
      } else {
        await client.from('branches').update(result).eq('id', branch['id']);
      }
      _invalidateBranchData();
      if (!mounted) return;
      AppSnackbar.success(
          context, branch == null ? 'Branch created.' : 'Branch updated.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _setActive(Map<String, dynamic> branch, bool active) async {
    final confirm = await showConfirmDialog(
      context,
      title: active ? S.reactivate : S.deactivate,
      message:
          '${active ? S.reactivate : S.deactivate} ${branch['name'] ?? ''}?',
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client
          .from('branches')
          .update({'is_active': active}).eq('id', branch['id']);
      _invalidateBranchData();
      if (!mounted) return;
      AppSnackbar.success(
          context, active ? 'Branch reactivated.' : 'Branch deactivated.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _select(Map<String, dynamic> branch) async {
    final id = branch['id'] as String?;
    if (id == null) return;
    ref.read(selectedBranchProvider.notifier).state = id;
    ref.read(branchSelectionSetProvider.notifier).state = true;
    _invalidateBranchData();
    if (!mounted) return;
    AppSnackbar.success(context, '${branch['name'] ?? 'Branch'} selected.');
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final selectedBranchId = ref.watch(selectedBranchProvider);
    final canEdit = can(role, Modules.branches, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.branches,
              subtitle:
                  canEdit ? null : '${S.view} ${S.branches.toLowerCase()}',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: S.add,
                      width: 120,
                      onPressed: () => _edit(null),
                    ),
                  ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (_branches.isEmpty)
              EmptyState(
                message: canEdit
                    ? 'No branches yet. Create one to start recording sales and stock.'
                    : 'No branches have been created yet. Ask a super admin to add one.',
                icon: Icons.add_business_outlined,
                actionLabel: canEdit ? S.add : null,
                onAction: canEdit ? () => _edit(null) : null,
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: 220,
                        child: AppDropdown<String>(
                          label: S.status,
                          value: _statusFilter ?? 'All',
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(
                                value: S.active, child: Text(S.active)),
                            DropdownMenuItem(
                                value: S.inactive, child: Text(S.inactive)),
                          ],
                          onChanged: (value) => setState(() =>
                              _statusFilter = value == 'All' ? null : value),
                        ),
                      ),
                    ),
                    Expanded(
                      child: DataTablePlus(
                        columns: const [
                          S.pharmacyName,
                          'Code',
                          S.address,
                          S.phone,
                          S.status,
                          'Created',
                        ],
                        rows: [
                          for (final branch in _filtered)
                            DataTablePlusRow(
                              cells: [
                                "${selectedBranchId == branch['id'] ? '✓ ' : ''}"
                                    "${(branch['name'] as String?) ?? '—'}",
                                (branch['code'] as String?) ?? '—',
                                (branch['address'] as String?) ?? '—',
                                (branch['phone'] as String?) ?? '—',
                                branch['is_active'] == true
                                    ? S.active
                                    : S.inactive,
                                branch['created_at'] == null
                                    ? '—'
                                    : formatDate(DateTime.parse(
                                        branch['created_at'] as String)),
                              ],
                              actions: [
                                // Delete: n/a by design — deactivate instead.
                                // Historical sales and stock reference branch ids.
                                if (canEdit && selectedBranchId != branch['id'])
                                  IconButton(
                                    tooltip: 'Select branch',
                                    icon: const Icon(Icons.check_circle_outline,
                                        size: 18),
                                    onPressed: () => _select(branch),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: S.edit,
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => _edit(branch),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: branch['is_active'] == true
                                        ? S.deactivate
                                        : S.reactivate,
                                    icon: Icon(
                                      branch['is_active'] == true
                                          ? Icons.person_off_outlined
                                          : Icons.person_outline,
                                      size: 18,
                                    ),
                                    onPressed: () => _setActive(
                                        branch, branch['is_active'] != true),
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

class _BranchFormDialog extends StatefulWidget {
  const _BranchFormDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: (initial?['name'] as String?) ?? '');
    _code = TextEditingController(text: (initial?['code'] as String?) ?? '');
    _address =
        TextEditingController(text: (initial?['address'] as String?) ?? '');
    _phone = TextEditingController(text: (initial?['phone'] as String?) ?? '');
    _active = initial?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? S.add : S.edit),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: S.pharmacyName,
                controller: _name,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? S.required : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Code',
                controller: _code,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? S.required : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: S.address,
                controller: _address,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: S.phone,
                controller: _phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(S.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
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
              'name': _name.text.trim(),
              'code': _code.text.trim(),
              'address': _address.text.trim(),
              'phone': _phone.text.trim(),
              'is_active': _active,
            });
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}
