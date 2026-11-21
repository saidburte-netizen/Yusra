import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../data/sales.dart';
import '../logic/receipts.dart';
import '../../../core/errors/app_error.dart';
import '../../inventory/widgets/responsive_ui.dart';

/// Return creation is n/a by design here: a return always belongs to an
/// existing invoice and is created from `SaleDetailScreen`, where the sold
/// lines and returnable quantities are known. This screen is the read-only
/// history plus reprint/view actions for returns that already exist.
class ReturnsScreen extends ConsumerWidget {
  const ReturnsScreen({super.key});

  Future<void> _reprint(
      BuildContext context, WidgetRef ref, SaleReturn entry) async {
    try {
      final settings = await ref.read(receiptSettingsProvider.future);
      await Receipts.printReturnNote(
        returnNo: entry.returnNo,
        invoiceNo: entry.invoiceNo ?? '—',
        createdAt: entry.createdAt ?? DateTime.now(),
        reason: entry.reason,
        refundMethod: entry.refundMethod,
        amount: entry.refundAmount,
        settings: settings,
      );
    } catch (error) {
      if (context.mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(saleReturnsProvider);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Sale returns',
              subtitle: 'Refunds and restocks, with reasons',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ResponsiveSecondaryButton(
                    label: 'Sales',
                    icon: Icons.arrow_back,
                    onPressed: () => context.go('/sales'),
                  ),
                ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () => ref.invalidate(saleReturnsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Expanded(
              child: returns.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return const EmptyState(
                      message: 'No returns recorded.',
                      icon: Icons.assignment_return_outlined,
                    );
                  }
                  final total = rows.fold<double>(
                      0, (sum, row) => sum + row.refundAmount);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${rows.length} returns  •  ${formatMoney(total)} refunded',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: ResponsiveDataTablePlus(
                            columns: const [
                              'Return no',
                              'Invoice',
                              'Date',
                              'Reason',
                              'Refund',
                              'Amount',
                            ],
                            rows: [
                              for (final entry in rows)
                                DataTablePlusRow(
                                  cells: [
                                    entry.returnNo,
                                    entry.invoiceNo ?? '—',
                                    entry.createdAt == null
                                        ? '—'
                                        : formatDateTime(entry.createdAt!),
                                    entry.reason,
                                    entry.refundMethod.replaceAll('_', ' '),
                                    formatMoney(entry.refundAmount),
                                  ],
                                  actions: [
                                    IconButton(
                                      tooltip: 'Reprint',
                                      icon: const Icon(Icons.print_outlined),
                                      onPressed: () =>
                                          _reprint(context, ref, entry),
                                    ),
                                    IconButton(
                                      tooltip: 'View invoice',
                                      icon: const Icon(
                                          Icons.receipt_long_outlined),
                                      onPressed: () =>
                                          context.go('/sales/${entry.saleId}'),
                                    ),
                                  ],
                                ),
                            ],
                            searchHint: 'Search returns…',
                            exportFileName: 'yusra-returns.csv',
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const ResponsiveLoadingSkeleton(lines: 4),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(saleReturnsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
