import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../inventory/data/inventory_providers.dart';

final _expectedExpensesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!SupabaseService.isReady) return const [];
  final branchId = ref.watch(branchScopeProvider);
  var query = SupabaseService.client
      .from('expected_expenses')
      .select(
          'id, name, category, amount, due_day, branch_id, is_active, notes')
      .eq('is_active', true);
  if (branchId != null) {
    query = query.or('branch_id.eq.$branchId,branch_id.is.null');
  }
  final rows = await query.order('due_day');
  return List<Map<String, dynamic>>.from(rows as List);
});

final _salaryExpectationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!SupabaseService.isReady) return const [];
  final branchId = ref.watch(branchScopeProvider);
  var query = SupabaseService.client
      .from('profiles')
      .select('id, full_name, email, monthly_salary, is_active')
      .eq('is_active', true);
  if (branchId != null) query = query.eq('branch_id', branchId);
  final rows = await query;
  return List<Map<String, dynamic>>.from(rows as List)
      .where((r) =>
          (r['monthly_salary'] is num
              ? (r['monthly_salary'] as num)
              : num.tryParse('${r['monthly_salary']}') ?? 0) >
          0)
      .toList();
});

class ExpectedExpensesScreen extends ConsumerWidget {
  const ExpectedExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expected = ref.watch(_expectedExpensesProvider);
    final salaries = ref.watch(_salaryExpectationsProvider);
    final auth = ref.watch(authProvider);
    final canManage = auth.profile?.role == AppRole.superAdmin ||
        auth.profile?.role == AppRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expected expenses'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add expected expense',
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: expected.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: AppErrorMapper.from(e).message,
          onRetry: () {
            ref.invalidate(_expectedExpensesProvider);
            ref.invalidate(_salaryExpectationsProvider);
          },
        ),
        data: (rows) {
          final salaryRows = salaries.valueOrNull ?? const [];
          final today = nowAddisAbaba();
          final day = today.day;
          final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
          final items = <_ExpectedItem>[];
          for (final r in rows) {
            final amount = _num(r['amount']).toDouble();
            final dueDay = _num(r['due_day']).toInt().clamp(1, daysInMonth);
            items.add(_ExpectedItem(
              id: r['id']?.toString(),
              name: (r['name'] as String?) ?? 'Expense',
              category: (r['category'] as String?) ?? 'Other',
              amount: amount,
              dueDay: dueDay,
              overdue: day > dueDay,
              source: 'planned',
              notes: r['notes'] as String?,
            ));
          }
          for (final r in salaryRows) {
            final amount = _num(r['monthly_salary']).toDouble();
            final dueDay = 30.clamp(1, daysInMonth);
            final name =
                ((r['full_name'] as String?)?.trim().isNotEmpty ?? false)
                    ? (r['full_name'] as String).trim()
                    : (r['email'] as String? ?? 'Staff');
            items.add(_ExpectedItem(
              name: 'Salary: $name',
              category: 'Salaries',
              amount: amount,
              dueDay: dueDay,
              overdue: day > dueDay,
              source: 'salary',
            ));
          }
          items.sort((a, b) {
            if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
            return a.dueDay.compareTo(b.dueDay);
          });
          final total = items.fold<double>(0, (s, i) => s + i.amount);
          final overdue = items
              .where((i) => i.overdue)
              .fold<double>(0, (s, i) => s + i.amount);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_expectedExpensesProvider);
              ref.invalidate(_salaryExpectationsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _chip('Expected this month', formatMoney(total)),
                    _chip('Overdue', formatMoney(overdue),
                        color: AppColors.danger),
                    _chip('Items', '${items.length}'),
                  ],
                ),
                const SizedBox(height: 16),
                for (final item in items)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        item.overdue
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_outlined,
                        color:
                            item.overdue ? AppColors.danger : AppColors.gold500,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                          '${item.category} · Due day ${item.dueDay}${item.overdue ? ' · Overdue' : ''}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatMoney(item.amount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          if (canManage && item.source == 'planned')
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') _edit(context, ref, item);
                                if (v == 'delete') _delete(context, ref, item);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Edit')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Delete')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child:
                        Center(child: Text('No expected expenses configured.')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static num _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  Widget _chip(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (color ?? AppColors.plum600).withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: (color ?? AppColors.gold500).withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, _ExpectedItem? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final amount = TextEditingController(
        text: item == null ? '' : item.amount.toStringAsFixed(2));
    final dueDay = TextEditingController(text: '${item?.dueDay ?? 30}');
    final notes = TextEditingController(text: item?.notes ?? '');
    String category = item?.category ?? 'Rent';
    final categories = ['Rent', 'Utilities', 'Salaries', 'Supplies', 'Other'];
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              item == null ? 'Add expected expense' : 'Edit expected expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: categories.contains(category) ? category : 'Other',
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c))
                  ],
                  onChanged: (v) =>
                      setDialogState(() => category = v ?? 'Other'),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(
                    controller: dueDay,
                    decoration:
                        const InputDecoration(labelText: 'Due day (1-31)'),
                    keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final payload = {
        'name': name.text.trim(),
        'category': category,
        'amount': double.tryParse(amount.text.trim()) ?? 0,
        'due_day': (int.tryParse(dueDay.text.trim()) ?? 30).clamp(1, 31),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'is_active': true,
      };
      final client = SupabaseService.client;
      if (item?.id == null) {
        final branchId = ref.read(branchScopeProvider);
        await client
            .from('expected_expenses')
            .insert({...payload, 'branch_id': branchId});
      } else {
        await client
            .from('expected_expenses')
            .update(payload)
            .eq('id', item!.id!);
      }
      ref.invalidate(_expectedExpensesProvider);
      if (context.mounted) {
        AppSnackbar.success(context, 'Expected expense saved.');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, _ExpectedItem item) async {
    if (item.id == null) return;
    try {
      await SupabaseService.client
          .from('expected_expenses')
          .update({'is_active': false}).eq('id', item.id!);
      ref.invalidate(_expectedExpensesProvider);
      if (context.mounted) {
        AppSnackbar.success(context, 'Expected expense removed.');
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    }
  }
}

class _ExpectedItem {
  const _ExpectedItem({
    this.id,
    required this.name,
    required this.category,
    required this.amount,
    required this.dueDay,
    required this.overdue,
    required this.source,
    this.notes,
  });
  final String? id;
  final String name;
  final String category;
  final double amount;
  final int dueDay;
  final bool overdue;
  final String source;
  final String? notes;
}
