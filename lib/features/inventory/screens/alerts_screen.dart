import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../../purchasing/data/purchasing.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/stock_rules.dart';
import '../widgets/stock_widgets.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/strings.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canOrder = can(role, Modules.purchaseOrders, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Stock alerts',
              subtitle: 'Low stock, expiring soon and expired batches',
              actions: [
                if (canOrder)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SecondaryButton(
                      label: 'Create purchase order',
                      icon: Icons.shopping_cart_outlined,
                      width: 210,
                      onPressed: _createPurchaseOrder,
                    ),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () {
                    ref.invalidate(lowStockProvider);
                    ref.invalidate(expiringBatchesProvider);
                    ref.invalidate(stockSummaryProvider);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Low stock'),
                Tab(text: 'Expiring soon'),
                Tab(text: 'Expired'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _lowStockTab(),
                  _batchTab(expired: false),
                  _batchTab(expired: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lowStockTab() {
    final state = ref.watch(lowStockProvider);
    return stockState(
      state,
      onRetry: () => ref.invalidate(lowStockProvider),
      builder: (items) => DataTablePlus(
        columns: const [
          'Medicine',
          'Available',
          'Reorder level',
          'Suggested order',
          'Nearest expiry'
        ],
        rows: [
          for (final row in items)
            DataTablePlusRow(
              cells: [
                row.name,
                '${row.availableQty}',
                '${row.reorderLevel}',
                '${StockRules.suggestedOrder(row.reorderLevel, row.availableQty)}',
                row.nearestExpiry == null
                    ? '—'
                    : formatDate(row.nearestExpiry!),
              ],
            ),
        ],
        exportFileName: 'yusra-low-stock.csv',
      ),
    );
  }

  Widget _batchTab({required bool expired}) {
    final state = ref.watch(expiringBatchesProvider);
    return stockState(
      state,
      onRetry: () => ref.invalidate(expiringBatchesProvider),
      builder: (items) {
        final visible = items.where((batch) {
          return expired ? batch.daysLeft < 0 : batch.daysLeft >= 0;
        }).toList();
        return DataTablePlus(
          columns: const ['Medicine', 'Batch', 'Expiry', 'Days', 'Quantity'],
          rows: [
            for (final batch in visible)
              DataTablePlusRow(
                cells: [
                  batch.medicineName ?? '—',
                  batch.batchNo,
                  formatDate(batch.expiryDate),
                  '${batch.daysLeft}',
                  '${batch.quantity}',
                ],
              ),
          ],
          exportFileName: expired ? 'yusra-expired.csv' : 'yusra-expiring.csv',
        );
      },
    );
  }

  Future<void> _createPurchaseOrder() async {
    final low =
        ref.read(lowStockProvider).valueOrNull ?? const <StockSummary>[];
    if (low.isEmpty) {
      if (mounted) {
        AppSnackbar.error(context, 'Nothing is below reorder level.');
      }
      return;
    }
    final suppliers = await SupplierOption.load(ref);
    if (suppliers.isEmpty) {
      if (mounted) AppSnackbar.error(context, 'Add a supplier first.');
      return;
    }
    if (!mounted) return;
    String supplierId = suppliers.first.id;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create purchase order'),
        content: SizedBox(
          width: 360,
          child: AppDropdown<String>(
            label: 'Supplier',
            value: supplierId,
            items: [
              for (final supplier in suppliers)
                DropdownMenuItem(
                    value: supplier.id, child: Text(supplier.name)),
            ],
            onChanged: (value) => supplierId = value ?? supplierId,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            label: 'Create',
            width: 120,
            onPressed: () => Navigator.pop(context, supplierId),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    if (!mounted) return;
    final branch = ref.read(branchScopeProvider);
    if (branch == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    try {
      final id = await ref.read(purchaseRepositoryProvider).createDraft(
        branchId: branch,
        supplierId: chosen,
        expectedDate: null,
        notes: 'Generated from low stock alerts',
        tax: 0,
        lines: [
          for (final row in low)
            PurchaseOrderItem(
              id: '',
              poId: '',
              medicineId: row.medicineId,
              quantityOrdered: StockRules.suggestedOrder(
                row.reorderLevel,
                row.availableQty,
              ),
              unitCost: row.costPrice,
              medicineName: row.name,
            ),
        ],
      );
      if (!mounted) return;
      AppSnackbar.success(context, 'Draft purchase order created.');
      ref.invalidate(purchaseOrdersProvider);
      context.go('/purchasing/orders/$id');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}
