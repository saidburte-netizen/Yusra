import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/stock_rules.dart';
import '../widgets/stock_widgets.dart';

class StockOverviewScreen extends ConsumerStatefulWidget {
  const StockOverviewScreen({super.key});

  @override
  ConsumerState<StockOverviewScreen> createState() =>
      _StockOverviewScreenState();
}

class _StockOverviewScreenState extends ConsumerState<StockOverviewScreen> {
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stockSummaryProvider);
    final alertDays = ref.watch(expiryAlertDaysProvider).value ?? 90;
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
              title: 'Stock overview',
              subtitle: 'Available, expired and low stock by medicine',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: 'Add stock',
                      icon: Icons.add,
                      width: 130,
                      onPressed: () => showAddStockDialog(context, ref),
                    ),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(stockSummaryProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            stockState(
              state,
              onRetry: () => ref.invalidate(stockSummaryProvider),
              builder: (rows) {
                final value = rows.fold<double>(
                  0,
                  (sum, row) => sum + row.availableQty * row.costPrice,
                );
                final units =
                    rows.fold<int>(0, (sum, row) => sum + row.availableQty);
                final visible = <StockSummary>[];
                final statusOf = <String, StockStatus>{};
                for (final row in rows) {
                  final status = StockRules.status(
                    available: row.availableQty,
                    expiredQty: row.expiredQty,
                    reorderLevel: row.reorderLevel,
                    daysToNearestExpiry: row.daysToNearestExpiry,
                    alertDays: alertDays,
                  );
                  statusOf[row.medicineId] = status;
                  if (_statusFilter == null ||
                      StockRules.label(status) == _statusFilter) {
                    visible.add(row);
                  }
                }
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ResponsiveGrid(
                        minTileWidth: 180,
                        children: [
                          StatCard(
                            title: 'Medicines',
                            value: '${rows.length}',
                            icon: Icons.medication_outlined,
                            color: AppColors.pink600,
                          ),
                          StatCard(
                            title: 'Units on hand',
                            value: '$units',
                            icon: Icons.inventory_2_outlined,
                            color: AppColors.gold700,
                          ),
                          if (showCost)
                            StatCard(
                              title: 'Stock value at cost',
                              value: formatMoneyWhole(value),
                              icon: Icons.account_balance_wallet_outlined,
                              color: AppColors.success,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: DataTablePlus(
                          columns: [
                            'Medicine',
                            'SKU',
                            'Available',
                            'Status',
                            'Nearest expiry',
                            if (showCost) 'Cost',
                            'Price',
                            '',
                          ],
                          rows: [
                            for (final row in visible)
                              DataTablePlusRow(
                                cells: [
                                  row.name,
                                  row.sku ?? '',
                                  '${row.availableQty} ${row.unit}',
                                  StockRules.label(statusOf[row.medicineId]!),
                                  row.nearestExpiry == null
                                      ? '—'
                                      : formatDate(row.nearestExpiry!),
                                  if (showCost) formatMoney(row.costPrice),
                                  formatMoney(row.sellingPrice),
                                  '',
                                ],
                                actions: [
                                  IconButton(
                                    tooltip: 'Details',
                                    icon:
                                        const Icon(Icons.open_in_new, size: 18),
                                    onPressed: () => context.go(
                                        '/inventory/medicines/${row.medicineId}'),
                                  ),
                                ],
                              ),
                          ],
                          filterChips:
                              StockStatus.values.map(StockRules.label).toList(),
                          selectedFilter: _statusFilter,
                          onFilterChanged: (value) =>
                              setState(() => _statusFilter = value),
                          exportFileName: 'yusra-stock.csv',
                        ),
                      ),
                    ],
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
