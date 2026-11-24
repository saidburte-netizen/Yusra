import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/state/invalidation.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../dashboard/dashboard_screen.dart' show dashboardRefreshProvider;
import '../inventory/data/inventory_providers.dart';

const List<String> expenseCategories = [
  'Rent',
  'Salaries',
  'Utilities',
  'Transport',
  'Supplies',
  'Other',
];

/// The database stores the `payment_method` enum, so the enum value is sent to
/// Supabase while the label is only shown in the UI.
class _PaymentMethod {
  const _PaymentMethod(this.value, this.label);

  final String value;
  final String label;
}

const List<_PaymentMethod> _paymentMethods = [
  _PaymentMethod('cash', 'Cash'),
  _PaymentMethod('bank_transfer', 'Bank transfer'),
  _PaymentMethod('mobile_money', 'Mobile money (Telebirr)'),
  _PaymentMethod('card', 'Card'),
];

String _paymentMethodLabel(String? value) {
  if (value == null) return '—';
  for (final method in _paymentMethods) {
    if (method.value == value) return method.label;
  }
  return value;
}

class _ExpenseFormResult {
  const _ExpenseFormResult(this.values, this.receiptBytes);

  final Map<String, dynamic> values;
  final Uint8List? receiptBytes;
}

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key, this.initialRows, this.initialError});

  /// Optional preloaded data keeps this screen pumpable in widget tests without
  /// a live Supabase client. Production routes use the plain constructor.
  final List<Map<String, dynamic>>? initialRows;
  final String? initialError;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _categoryFilter;
  DateTimeRange _range = () {
    final now = nowAddisAbaba();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    return DateTimeRange(start: start, end: end);
  }();
  bool _handledAction = false;
  Map<String, String> _creatorNames = const {};
  bool get _testMode =>
      widget.initialRows != null || widget.initialError != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialRows != null || widget.initialError != null) {
      _rows = widget.initialRows ?? const [];
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
        if (mounted) _edit(null);
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
      final profile = ref.read(authProvider).profile;
      final allBranches = profile == null || canSeeAllBranches(profile.role);
      final from =
          DateTime.utc(_range.start.year, _range.start.month, _range.start.day)
              .subtract(addisAbabaOffset)
              .toIso8601String();
      final to = DateTime.utc(_range.end.year, _range.end.month, _range.end.day)
          .add(const Duration(days: 1))
          .subtract(addisAbabaOffset)
          .toIso8601String();

      var query = SupabaseService.client
          .from('expenses')
          .select()
          .gte('expense_date', from)
          .lt('expense_date', to);
      final branchId = profile?.branchId;
      if (!allBranches && branchId != null) {
        query = query.eq('branch_id', branchId);
      }
      final result = await query.order('expense_date', ascending: false);
      final rows = List<Map<String, dynamic>>.from(result as List);
      final creatorIds = rows
          .map((r) => r['created_by']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      var creatorNames = <String, String>{};
      if (creatorIds.isNotEmpty) {
        try {
          final creators = await SupabaseService.client
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', creatorIds);
          for (final c in creators as List) {
            final m = c as Map<String, dynamic>;
            final id = m['id']?.toString();
            if (id != null)
              creatorNames[id] = (m['full_name'] as String?)?.trim() ?? '';
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _creatorNames = creatorNames;
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

  List<Map<String, dynamic>> get _filtered => _rows.where((row) {
        if (_categoryFilter == null) return true;
        return row['category'] == _categoryFilter;
      }).toList();

  double _amount(Map<String, dynamic> row) {
    final value = row['amount'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  double get _monthlyTotal {
    var total = 0.0;
    for (final row in _rows) {
      total += _amount(row);
    }
    return total;
  }

  Map<String, double> get _byCategory {
    final totals = <String, double>{
      for (final category in expenseCategories) category: 0,
    };
    for (final row in _rows) {
      final category = (row['category'] as String?) ?? 'Other';
      totals[category] = (totals[category] ?? 0) + _amount(row);
    }
    totals.removeWhere((_, value) => value <= 0);
    return totals;
  }

  Future<void> _edit(Map<String, dynamic>? expense) async {
    final result = await showDialog<_ExpenseFormResult>(
      context: context,
      builder: (_) => _ExpenseFormDialog(initial: expense),
    );
    if (result == null || !mounted) return;
    try {
      final isNew = expense == null;
      if (_testMode) {
        final id = isNew
            ? 'test-${DateTime.now().microsecondsSinceEpoch}'
            : expense['id'];
        final row = <String, dynamic>{
          ...?expense,
          ...result.values,
          'id': id,
          'status': expense?['status'] ?? 'pending',
          'created_by': ref.read(authProvider).profile?.id,
        };
        setState(() {
          if (isNew) {
            _rows = [row, ..._rows];
          } else {
            _rows = _rows.map((r) => r['id'] == id ? row : r).toList();
          }
        });
        if (!mounted) return;
        AppSnackbar.success(
            context, isNew ? 'Expense created.' : 'Expense updated.');
        return;
      }
      final client = SupabaseService.client;
      // The expense always belongs to a concrete branch; an unscoped admin has
      // to pick one before creating a record.
      final branchId = isNew
          ? ref.read(branchScopeProvider)
          : expense['branch_id'] as String?;
      if (branchId == null) {
        AppSnackbar.error(context, S.chooseBranchFirst);
        return;
      }

      late final String expenseId;
      if (isNew) {
        final inserted = await client
            .from('expenses')
            .insert(
                {...result.values, 'branch_id': branchId, 'status': 'pending'})
            .select('id')
            .single();
        expenseId = inserted['id'] as String;
      } else {
        expenseId = expense['id'] as String;
        await client.from('expenses').update(result.values).eq('id', expenseId);
      }

      // The receipts bucket is private, so the storage path (not a public URL)
      // is stored on the row. The expense id is only known after the insert.
      if (result.receiptBytes != null) {
        final path = 'receipts/$branchId/$expenseId/receipt.jpg';
        await client.storage.from('receipts').uploadBinary(
              path,
              result.receiptBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        await client
            .from('expenses')
            .update({'receipt_path': path}).eq('id', expenseId);
      }

      if (!mounted) return;
      ref.read(dashboardRefreshProvider.notifier).state++;
      AppSnackbar.success(
          context, isNew ? 'Expense created.' : 'Expense updated.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<String?> _delete(Map<String, dynamic> expense) async {
    await SupabaseService.client
        .from('expenses')
        .delete()
        .eq('id', expense['id']);
    await _load();
    return 'Expense deleted.';
  }

  Future<void> _setStatus(Map<String, dynamic> expense, String status) async {
    final role = ref.read(authProvider).profile?.role;
    if (role != AppRole.superAdmin &&
        role != AppRole.admin &&
        role != AppRole.accountant) {
      AppSnackbar.error(context, 'Access denied.');
      return;
    }
    try {
      await SupabaseService.client.rpc('set_expense_status', params: {
        'p_expense': expense['id'],
        'p_status': status,
      });
      if (!mounted) return;
      AppSnackbar.success(context,
          status == 'approved' ? 'Expense approved.' : 'Expense rejected.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  /// Receipts live in a private bucket, so a short-lived signed URL is needed
  /// each time one is opened.
  Future<void> _openReceipt(String path) async {
    try {
      final url = await SupabaseService.client.storage
          .from('receipts')
          .createSignedUrl(path, 3600);
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.expenses, PermAction.edit);
    final canApprove = role == AppRole.superAdmin ||
        role == AppRole.admin ||
        role == AppRole.accountant;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.expenses,
              subtitle: S.expenseCategories,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                        '${formatDate(_range.start, pattern: 'dd MMM')} - ${formatDate(_range.end, pattern: 'dd MMM yyyy')}'),
                  ),
                ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: S.add,
                      width: 110,
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ResponsiveGrid(
                        minTileWidth: 220,
                        children: [
                          StatCard(
                            title: 'Total',
                            value: formatMoneyWhole(_monthlyTotal),
                            icon: Icons.account_balance_wallet_outlined,
                            color: AppColors.gold700,
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(S.byCategory,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 12),
                                  if (_byCategory.isEmpty)
                                    const Text(S.noData)
                                  else
                                    ..._byCategory.entries
                                        .map((entry) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(entry.key),
                                                      MoneyText(entry.value),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  LinearProgressIndicator(
                                                    value: _monthlyTotal == 0
                                                        ? 0
                                                        : entry.value /
                                                            _monthlyTotal,
                                                    minHeight: 5,
                                                  ),
                                                ],
                                              ),
                                            )),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: 220,
                          child: AppDropdown<String>(
                            label: S.category,
                            value: _categoryFilter ?? 'All',
                            items: [
                              const DropdownMenuItem(
                                  value: 'All', child: Text('All')),
                              for (final category in expenseCategories)
                                DropdownMenuItem(
                                    value: category, child: Text(category)),
                            ],
                            onChanged: (value) => setState(() =>
                                _categoryFilter =
                                    value == 'All' ? null : value),
                          ),
                        ),
                      ),
                      _filtered.isEmpty
                          ? const EmptyState(
                              message: 'No expenses for this date range.',
                              icon: Icons.account_balance_wallet_outlined)
                          : DataTablePlus(
                              columns: const [
                                'Date',
                                S.category,
                                'Amount',
                                'Note',
                                'Who added it',
                                S.paymentMethod,
                                'Status',
                              ],
                              exportFileName: 'yusra-expenses.csv',
                              rows: [
                                for (final expense in _filtered)
                                  DataTablePlusRow(
                                    cells: [
                                      expense['expense_date'] == null
                                          ? '—'
                                          : formatDate(DateTime.parse(
                                              expense['expense_date']
                                                  as String)),
                                      (expense['category'] as String?) ?? '—',
                                      formatMoney(_amount(expense)),
                                      (expense['description'] as String?)
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? (expense['description'] as String)
                                          : '—',
                                      _creatorNames[expense['created_by']
                                                      ?.toString()]
                                                  ?.isNotEmpty ==
                                              true
                                          ? _creatorNames[expense['created_by']
                                              ?.toString()]!
                                          : (expense['created_by']
                                                  ?.toString()
                                                  .substring(0, 8) ??
                                              '—'),
                                      _paymentMethodLabel(
                                          expense['payment_method'] as String?),
                                      (expense['status'] as String?) ??
                                          'approved',
                                    ],
                                    actions: [
                                      if (expense['receipt_path'] != null)
                                        IconButton(
                                          tooltip: S.receiptPhoto,
                                          icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 18),
                                          onPressed: () => _openReceipt(
                                              expense['receipt_path']
                                                  as String),
                                        ),
                                      if (canApprove &&
                                          (expense['status'] as String?) ==
                                              'pending')
                                        IconButton(
                                          tooltip: 'Approve',
                                          icon: const Icon(
                                              Icons.check_circle_outline,
                                              size: 18),
                                          onPressed: () =>
                                              _setStatus(expense, 'approved'),
                                        ),
                                      if (canApprove &&
                                          (expense['status'] as String?) ==
                                              'pending')
                                        IconButton(
                                          tooltip: 'Reject',
                                          icon: const Icon(
                                              Icons.cancel_outlined,
                                              size: 18),
                                          onPressed: () =>
                                              _setStatus(expense, 'rejected'),
                                        ),
                                      if (canEdit)
                                        RowActions(actions: [
                                          RowAction(
                                            label: S.edit,
                                            icon: Icons.edit_outlined,
                                            onSelected: () async {
                                              await _edit(expense);
                                              return null;
                                            },
                                            mutation: Mutation.createExpense,
                                          ),
                                          RowAction(
                                            label: S.delete,
                                            icon: Icons.delete_outline,
                                            danger: true,
                                            confirmTitle: S.delete,
                                            confirmMessage:
                                                '${S.confirmDelete}\n${expense['category'] ?? ''}',
                                            onSelected: () => _delete(expense),
                                            mutation: Mutation.deleteExpense,
                                          ),
                                        ]),
                                    ],
                                  ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = expenseCategories.first;
  String _paymentMethod = _paymentMethods.first.value;
  DateTime _date = nowAddisAbaba();
  Uint8List? _receiptBytes;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _amountController.text = initial['amount']?.toString() ?? '';
      _descriptionController.text = (initial['description'] as String?) ?? '';
      _category = (initial['category'] as String?) ?? _category;
      _paymentMethod = (initial['payment_method'] as String?) ?? _paymentMethod;
      if (initial['expense_date'] != null) {
        _date = DateTime.parse(initial['expense_date'] as String).toLocal();
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _receiptBytes = bytes);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final values = <String, dynamic>{
      'amount': parseMoney(_amountController.text),
      'category': _category,
      'payment_method': _paymentMethod,
      'expense_date': toAddisAbaba(_date).toUtc().toIso8601String(),
      'description': _descriptionController.text.trim(),
    };
    Navigator.pop(context, _ExpenseFormResult(values, _receiptBytes));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? S.add : S.edit),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoneyField(
                  label: 'Amount',
                  controller: _amountController,
                  validator: (value) =>
                      value == null || value <= 0 ? S.required : null,
                ),
                const SizedBox(height: 12),
                AppDropdown<String>(
                  label: S.category,
                  value: _category,
                  items: [
                    for (final category in expenseCategories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: 12),
                AppDropdown<String>(
                  label: S.paymentMethod,
                  value: _paymentMethod,
                  items: [
                    for (final method in _paymentMethods)
                      DropdownMenuItem(
                          value: method.value, child: Text(method.label)),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value!),
                ),
                const SizedBox(height: 12),
                DatePickerField(
                  label: 'Date',
                  value: _date,
                  emptyText: 'Select date',
                  onChanged: (value) => setState(() => _date = value),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Description',
                  controller: _descriptionController,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickReceipt,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(_receiptBytes == null
                        ? S.receiptPhoto
                        : 'Receipt attached'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(S.cancel)),
        ElevatedButton(onPressed: _submit, child: const Text(S.save)),
      ],
    );
  }
}
