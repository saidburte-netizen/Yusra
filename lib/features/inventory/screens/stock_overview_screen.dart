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
    final alertDays = ref.watch(expiryAlertDaysProvider).valueOrNull ?? 90;
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.stock, PermAction.edit);
    final showCost = role != AppRole.cashier;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    final actionChips = <Widget>[
      if (canEdit)
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Add stock'),
          onPressed: () => showAddStockDialog(context, ref),
        ),
      if (canEdit)
        ActionChip(
          avatar: const Icon(Icons.playlist_add_check_outlined, size: 18),
          label: const Text('Opening stock'),
          onPressed: () => context.go('/inventory/opening-stock'),
        ),
      if (canEdit && can(role, Modules.purchaseOrders, PermAction.edit))
        ActionChip(
          avatar: const Icon(Icons.shopping_cart_outlined, size: 18),
          label: const Text('Needs ordering'),
          onPressed: () => context.go('/inventory/needs-ordering'),
        ),
      ActionChip(
        avatar: const Icon(Icons.monitor_heart_outlined, size: 18),
        label: const Text('Drug status'),
        onPressed: () => context.go('/inventory/drug-status'),
      ),
      ActionChip(
        avatar: const Icon(Icons.medication_outlined, size: 18),
        label: const Text('Medicines'),
        onPressed: () => context.go('/inventory/medicines'),
      ),
      ActionChip(
        avatar: const Icon(Icons.qr_code_2_outlined, size: 18),
        label: const Text('Batches'),
        onPressed: () => context.go('/inventory/batches'),
      ),
      ActionChip(
        avatar: const Icon(Icons.swap_horiz_outlined, size: 18),
        label: const Text('Movements'),
        onPressed: () => context.go('/inventory/movements'),
      ),
      ActionChip(
        avatar: const Icon(Icons.tune_outlined, size: 18),
        label: const Text('Adjustments'),
        onPressed: () => context.go('/inventory/adjustments'),
      ),
      ActionChip(
        avatar: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Stocktake'),
        onPressed: () => context.go('/inventory/stocktake'),
      ),
      ActionChip(
        avatar: const Icon(Icons.category_outlined, size: 18),
        label: const Text('Categories'),
        onPressed: () => context.go('/inventory/categories'),
      ),
      ActionChip(
        avatar: const Icon(Icons.warning_amber_outlined, size: 18),
        label: const Text('Alerts'),
        onPressed: () => context.go('/inventory/alerts'),
      ),
      ActionChip(
        avatar: const Icon(Icons.refresh, size: 18),
        label: const Text('Refresh'),
        onPressed: () => ref.invalidate(stockSummaryProvider),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, narrow ? 88 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Stock overview',
                subtitle: 'Available, expired and low stock by medicine',
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: actionChips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => actionChips[i],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: stockState(
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
                    final cards = <Widget>[
                      StatCard(
                        compact: narrow,
                        title: 'Medicines',
                        value: '${rows.length}',
                        icon: Icons.medication_outlined,
                        color: AppColors.pink600,
                      ),
                      StatCard(
                        compact: narrow,
                        title: 'Units on hand',
                        value: '$units',
                        icon: Icons.inventory_2_outlined,
                        color: AppColors.gold700,
                      ),
                      if (showCost)
                        StatCard(
                          compact: narrow,
                          title: 'Stock value at cost',
                          value: formatMoneyWhole(value),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppColors.success,
                        ),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ResponsiveGrid(
                          minTileWidth: narrow ? 150 : 180,
                          spacing: narrow ? 10 : 14,
                          children: cards,
                        ),
                        const SizedBox(height: 12),
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
                                      icon: const Icon(Icons.open_in_new,
                                          size: 18),
                                      onPressed: () => context.go(
                                          '/inventory/medicines/${row.medicineId}'),
                                    ),
                                  ],
                                ),
                            ],
                            filterChips: StockStatus.values
                                .map(StockRules.label)
                                .toList(),
                            selectedFilter: _statusFilter,
                            onFilterChanged: (value) =>
                                setState(() => _statusFilter = value),
                            exportFileName: 'yusra-stock.csv',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
