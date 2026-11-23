import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/responsive_ui.dart';

/// Batch rows are immutable stock history: deleting one would break the
/// movement ledger and stock valuation. There is deliberately no delete (and
/// no deactivate) action here — use the Adjust action to correct a count.
class BatchesScreen extends ConsumerStatefulWidget {
  const BatchesScreen({super.key});

  @override
  ConsumerState<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends ConsumerState<BatchesScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(batchesProvider(null));
    final alertDays = ref.watch(expiryAlertDaysProvider).valueOrNull ?? 90;
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.stock, PermAction.edit);
    final showCost = role != AppRole.cashier;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Stock batches',
              subtitle: 'Expiry and quantity per batch',
              actions: [
                if (canEdit)
                  ResponsivePrimaryButton(
                    label: 'Add stock',
                    icon: Icons.add,
                    onPressed: () => showAddStockDialog(context, ref),
                  ),
              ],
            ),
            stockState(
              state,
              onRetry: () => ref.invalidate(batchesProvider(null)),
              builder: (items) {
                final visible = items.where((batch) {
                  return switch (_filter) {
                    'Expired' => batch.daysLeft < 0,
                    'Under 30 days' =>
                      batch.daysLeft >= 0 && batch.daysLeft < 30,
                    'Near expiry' =>
                      batch.daysLeft >= 30 && batch.daysLeft <= alertDays,
                    _ => true,
                  };
                }).toList();
                return Expanded(
                  child: ResponsiveDataTablePlus(
                    columns: [
                      'Medicine',
                      'Batch',
                      'Expiry',
                      'Quantity',
                      if (showCost) 'Cost',
                      'Alert',
                      '',
                    ],
                    rows: [
                      for (final batch in visible)
                        DataTablePlusRow(
                          cells: [
                            batch.medicineName ?? '—',
                            batch.batchNo,
                            formatDate(batch.expiryDate),
                            '${batch.quantity}',
                            if (showCost) formatMoney(batch.costPrice),
                            batch.daysLeft < 0
                                ? 'Expired'
                                : '${batch.daysLeft} days',
                            '',
                          ],
                          actions: [
                            expiryChip(batch, alertDays),
                            if (canEdit)
                              IconButton(
                                tooltip: 'Adjust',
                                icon: const Icon(Icons.tune, size: 18),
                                onPressed: () => showAdjustStockDialog(
                                  context,
                                  ref,
                                  batch: batch,
                                ),
                              ),
                          ],
                        ),
                    ],
                    filterChips: const [
                      'Expired',
                      'Under 30 days',
                      'Near expiry'
                    ],
                    selectedFilter: _filter,
                    onFilterChanged: (value) => setState(() => _filter = value),
                    exportFileName: 'yusra-batches.csv',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
