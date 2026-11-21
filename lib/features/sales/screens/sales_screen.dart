import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../data/sales.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../../core/errors/app_error.dart';

typedef SaleFilterArgs = ({
  DateTime? from,
  DateTime? to,
  String? cashierId,
  String? status,
  String? method,
  String? invoice,
});

const SaleFilterArgs _allSales = (
  from: null,
  to: null,
  cashierId: null,
  status: null,
  method: null,
  invoice: null,
);

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  SaleFilterArgs _filter = _allSales;

  Future<void> _pickRange() async {
    final now = nowAddisAbaba();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _filter.from != null && _filter.to != null
          ? DateTimeRange(start: _filter.from!, end: _filter.to!)
          : null,
      helpText: 'Select date range',
    );
    if (range == null) return;
    setState(() {
      _filter = (
        from: range.start,
        to: range.end.add(const Duration(days: 1)),
        cashierId: _filter.cashierId,
        status: _filter.status,
        method: _filter.method,
        invoice: _filter.invoice,
      );
    });
  }

  Future<void> _void(Sale sale) async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.saleReturns, PermAction.edit)) {
      AppSnackbar.error(context, 'Only a pharmacist or admin can void a sale.');
      return;
    }
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Void invoice ${sale.invoiceNo}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The sale will be cancelled and the stock restored.'),
            const SizedBox(height: 12),
            AppTextField(label: 'Reason', controller: reason, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              if (reason.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Void sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(salesRepositoryProvider)
          .voidSale(sale.id, reason.text.trim());
      ref.invalidate(salesProvider);
      if (mounted) AppSnackbar.success(context, 'Sale voided.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final sales = ref.watch(salesProvider(_filter));
    final cashiers = ref.watch(cashiersProvider);
    final showVoid = can(role, Modules.saleReturns, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Sales history',
              subtitle: 'Invoices, receipts and returns',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SecondaryButton(
                    label: 'Returns',
                    icon: Icons.assignment_return_outlined,
                    width: 110,
                    onPressed: () => context.go('/sales/returns'),
                  ),
                ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () => ref.invalidate(salesProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(_filter.from == null
                      ? 'All dates'
                      : '${formatDate(_filter.from!)} – ${formatDate(_filter.to!)}'),
                  onPressed: _pickRange,
                ),
                if (_filter.from != null)
                  IconButton(
                    tooltip: 'Clear dates',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _filter = (
                        from: null,
                        to: null,
                        cashierId: _filter.cashierId,
                        status: _filter.status,
                        method: _filter.method,
                        invoice: _filter.invoice,
                      );
                    }),
                  ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String?>(
                    value: _filter.cashierId,
                    decoration: const InputDecoration(
                        labelText: 'Cashier', isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All cashiers')),
                      ...cashiers.valueOrNull?.map(
                            (row) => DropdownMenuItem(
                              value: row['id'] as String,
                              child: Text(
                                  row['full_name'] as String? ?? 'Cashier'),
                            ),
                          ) ??
                          const [],
                    ],
                    onChanged: (value) => setState(() {
                      _filter = (
                        from: _filter.from,
                        to: _filter.to,
                        cashierId: value,
                        status: _filter.status,
                        method: _filter.method,
                        invoice: _filter.invoice,
                      );
                    }),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    value: _filter.status,
                    decoration: const InputDecoration(
                        labelText: 'Status', isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: null, child: Text('All statuses')),
                      DropdownMenuItem(
                          value: 'completed', child: Text('Completed')),
                      DropdownMenuItem(value: 'voided', child: Text('Voided')),
                      DropdownMenuItem(
                          value: 'partially_returned',
                          child: Text('Part returned')),
                      DropdownMenuItem(
                          value: 'returned', child: Text('Returned')),
                    ],
                    onChanged: (value) => setState(() {
                      _filter = (
                        from: _filter.from,
                        to: _filter.to,
                        cashierId: _filter.cashierId,
                        status: value,
                        method: _filter.method,
                        invoice: _filter.invoice,
                      );
                    }),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    value: _filter.method,
                    decoration: const InputDecoration(
                        labelText: 'Payment', isDense: true),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All methods')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(
                          value: 'mobile_money', child: Text('Mobile money')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(
                          value: 'bank_transfer', child: Text('Bank transfer')),
                    ],
                    onChanged: (value) => setState(() {
                      _filter = (
                        from: _filter.from,
                        to: _filter.to,
                        cashierId: _filter.cashierId,
                        status: _filter.status,
                        method: value,
                        invoice: _filter.invoice,
                      );
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: sales.when(
                data: (rows) {
                  final total =
                      rows.fold<double>(0, (sum, sale) => sum + sale.total);
                  if (rows.isEmpty) {
                    return const EmptyState(
                      message: 'No sales match these filters.',
                      icon: Icons.receipt_long,
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${rows.length} invoices  •  ${formatMoney(total)} total',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: DataTablePlus(
                            columns: const [
                              'Invoice',
                              'Date',
                              'Cashier',
                              'Customer',
                              'Total',
                              'Paid',
                              'Status',
                            ],
                            rows: [
                              for (final sale in rows)
                                DataTablePlusRow(
                                  cells: [
                                    sale.invoiceNo,
                                    sale.createdAt == null
                                        ? '—'
                                        : formatDateTime(sale.createdAt!),
                                    sale.cashierName ?? '—',
                                    sale.customerName ?? 'Walk-in',
                                    formatMoney(sale.total),
                                    formatMoney(sale.paid),
                                    sale.status.toUpperCase(),
                                  ],
                                  actions: [
                                    IconButton(
                                      tooltip: 'View',
                                      icon:
                                          const Icon(Icons.visibility_outlined),
                                      onPressed: () =>
                                          context.go('/sales/${sale.id}'),
                                    ),
                                    if (sale.status == 'completed' && showVoid)
                                      IconButton(
                                        tooltip: 'Void',
                                        icon: const Icon(Icons.cancel_outlined,
                                            color: AppColors.danger),
                                        onPressed: () => _void(sale),
                                      ),
                                  ],
                                ),
                            ],
                            searchHint: 'Search invoice or customer…',
                            exportFileName: 'yusra-sales.csv',
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const LoadingSkeleton(lines: 5),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(salesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cashier list for the filter. Kept separate so a failure here never blocks
/// the sales table.
final cashiersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (!SupabaseService.isReady) return const [];
  var query = SupabaseService.client.from('profiles').select('id, full_name');
  final branchId = ref.read(branchScopeProvider);
  if (branchId != null) {
    query = query.eq('branch_id', branchId);
  }
  final rows = await query.order('full_name') as List;
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});
