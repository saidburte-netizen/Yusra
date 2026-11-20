import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

/// Pharmacy branches. Only a super_admin may edit; admins get a read-only view
/// (see the permission matrix).
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final rows = await SupabaseService.client
          .from('branches')
          .select()
          .order('name');
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
        await client.from('branches').insert(result);
      } else {
        await client.from('branches').update(result).eq('id', branch['id']);
      }
      if (!mounted) return;
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _setActive(Map<String, dynamic> branch, bool active) async {
    final confirm = await showConfirmDialog(
      context,
      title: active ? S.reactivate : S.deactivate,
      message: '${active ? S.reactivate : S.deactivate} ${branch['name'] ?? ''}?',
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client
          .from('branches')
          .update({'is_active': active})
          .eq('id', branch['id']);
      if (!mounted) return;
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.branches, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.branches,
              subtitle: canEdit ? null : '${S.view} ${S.branches.toLowerCase()}',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: S.add,
                      icon: Icons.add_business_outlined,
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
            else
              Expanded(
                child: DataTablePlus(
                  columns: const [
                    S.pharmacyName,
                    'Code',
                    S.address,
                    S.phone,
                    S.status,
                    'Created',
                    S.actionLabel,
                  ],
                  filterChips: const [S.active, S.inactive],
                  selectedFilter: _statusFilter,
                  onFilterChanged: (value) => setState(() => _statusFilter = value),
                  rows: [
                    for (final branch in _filtered)
                      DataTablePlusRow(
                        cells: [
                          (branch['name'] as String?) ?? '—',
                          (branch['code'] as String?) ?? '—',
                          (branch['address'] as String?) ?? '—',
                          (branch['phone'] as String?) ?? '—',
                          branch['is_active'] == true ? S.active : S.inactive,
                          branch['created_at'] == null
                              ? '—'
                              : formatDate(DateTime.parse(branch['created_at'] as String)),
                        ],
                        actions: [
                          if (canEdit)
                            IconButton(
                              tooltip: S.edit,
                              icon: const Icon(Icons.edit_outlined, size: 18),
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
                              onPressed: () =>
                                  _setActive(branch, branch['is_active'] != true),
                            ),
                        ],
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
    _address = TextEditingController(text: (initial?['address'] as String?) ?? '');
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
                validator: (v) => v == null || v.trim().isEmpty ? S.required : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Code',
                controller: _code,
                validator: (v) => v == null || v.trim().isEmpty ? S.required : null,
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
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
