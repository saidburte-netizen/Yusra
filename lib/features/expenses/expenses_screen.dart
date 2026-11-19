import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';

const List<String> expenseCategories = [
  'Rent',
  'Salaries',
  'Utilities',
  'Transport',
  'Supplies',
  'Other',
];

const List<String> paymentMethods = ['Cash', 'Bank transfer', 'Telebirr', 'Cheque'];

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _categoryFilter;
  DateTime _month = nowAddisAbaba();

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
      final profile = ref.read(authProvider).profile;
      final allBranches = profile == null || canSeeAllBranches(profile.role);
      final from = DateTime.utc(_month.year, _month.month)
          .subtract(addisAbabaOffset)
          .toIso8601String();
      final to = DateTime.utc(_month.year, _month.month + 1)
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
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(result as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExpenseFormDialog(initial: expense),
    );
    if (result == null) return;
    try {
      final client = SupabaseService.client;
      if (expense == null) {
        await client.from('expenses').insert(result);
      } else {
        await client.from('expenses').update(result).eq('id', expense['id']);
      }
      if (!mounted) return;
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> expense) async {
    final confirm = await showConfirmDialog(
      context,
      title: S.delete,
      message: '${S.confirmDelete}\n${expense['category'] ?? ''}',
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client
          .from('expenses')
          .delete()
          .eq('id', expense['id']);
      if (!mounted) return;
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime.utc(2020),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.expenses, PermAction.edit);

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
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(formatDate(_month, pattern: 'MMM yyyy')),
                  ),
                ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: S.add,
                      icon: Icons.add,
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
                child: Column(
                  children: [
                    ResponsiveGrid(
                      minTileWidth: 220,
                      children: [
                        StatCard(
                          title: S.monthlyTotal,
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
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 12),
                                if (_byCategory.isEmpty)
                                  const Text(S.noData)
                                else
                                  ..._byCategory.entries.map((entry) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(entry.key),
                                                MoneyText(entry.value),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            LinearProgressIndicator(
                                              value: _monthlyTotal == 0
                                                  ? 0
                                                  : entry.value / _monthlyTotal,
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
                    Expanded(
                      child: DataTablePlus(
                        columns: const [
                          'Date',
                          S.category,
                          'Amount',
                          S.paymentMethod,
                          'Note',
                          S.actionLabel,
                        ],
                        filterChips: expenseCategories,
                        selectedFilter: _categoryFilter,
                        onFilterChanged: (value) =>
                            setState(() => _categoryFilter = value),
                        exportFileName: 'yusra-expenses.csv',
                        rows: [
                          for (final expense in _filtered)
                            DataTablePlusRow(
                              cells: [
                                expense['expense_date'] == null
                                    ? '—'
                                    : formatDate(
                                        DateTime.parse(expense['expense_date'] as String)),
                                (expense['category'] as String?) ?? '—',
                                formatMoney(_amount(expense)),
                                (expense['payment_method'] as String?) ?? '—',
                                (expense['note'] as String?) ?? '—',
                                '',
                              ],
                              actions: [
                                if (canEdit)
                                  IconButton(
                                    tooltip: S.edit,
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _edit(expense),
                                  ),
                                if (canEdit)
                                  IconButton(
                                    tooltip: S.delete,
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () => _delete(expense),
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

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _category = expenseCategories.first;
  String _paymentMethod = paymentMethods.first;
  DateTime _date = nowAddisAbaba();
  Uint8List? _receiptBytes;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _amountController.text = initial['amount']?.toString() ?? '';
      _noteController.text = (initial['note'] as String?) ?? '';
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
    _noteController.dispose();
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

  Future<String?> _uploadReceipt() async {
    if (_receiptBytes == null) return null;
    final path = 'receipts/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await SupabaseService.client.storage
        .from('receipts')
        .uploadBinary(path, _receiptBytes!,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
    return SupabaseService.client.storage.from('receipts').getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _uploading = true);
    try {
      final body = <String, dynamic>{
        'amount': parseMoney(_amountController.text),
        'category': _category,
        'payment_method': _paymentMethod,
        'expense_date': toAddisAbaba(_date).toUtc().toIso8601String(),
        'note': _noteController.text.trim(),
      };
      final receiptUrl = await _uploadReceipt();
      if (receiptUrl != null) body['receipt_url'] = receiptUrl;
      if (!mounted) return;
      Navigator.pop(context, body);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppSnackbar.error(context, e.toString());
    }
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
                    for (final method in paymentMethods)
                      DropdownMenuItem(value: method, child: Text(method)),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value!),
                ),
                const SizedBox(height: 12),
                DatePickerField(
                  label: 'Date',
                  value: _date,
                  onChanged: (value) => setState(() => _date = value),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Note',
                  controller: _noteController,
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        ElevatedButton(
          onPressed: _uploading ? null : _submit,
          child: _uploading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(S.save),
        ),
      ],
    );
  }
}
