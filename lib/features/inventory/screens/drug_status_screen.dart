import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/permissions.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../data/drug_status_providers.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/responsive_ui.dart';

class DrugStatusScreen extends ConsumerStatefulWidget {
  const DrugStatusScreen({super.key});

  @override
  ConsumerState<DrugStatusScreen> createState() => _DrugStatusScreenState();
}

class _DrugStatusScreenState extends ConsumerState<DrugStatusScreen> {
  String _query = '';
  String _filter = 'All';
  String? _busyMedicineId;

  @override
  void initState() {
    super.initState();
    ref.read(stockAlertRealtimeProvider);
    ref.invalidate(drugStatusProvider);
    ref.invalidate(stockSummaryProvider);
    ref.invalidate(lowStockAlertsProvider);
  }

  Future<void> _orderNow(DrugStatusItem item) async {
    if (_busyMedicineId != null) return;
    final branch = ref.read(branchScopeProvider);
    if (branch == null || branch.isEmpty) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    final supplierId = item.supplierId;
    if (supplierId == null || supplierId.isEmpty) {
      AppSnackbar.error(
          context, 'Set a preferred supplier for ${item.medicine.name} first.');
      return;
    }

    setState(() => _busyMedicineId = item.medicine.id);
    try {
      final ids =
          await ref.read(inventoryRepositoryProvider).createDraftPurchaseOrders(
                branchId: branch,
                lines: [
                  {
                    'supplier_id': supplierId,
                    'medicine_id': item.medicine.id,
                    'quantity': item.suggestedOrderQty,
                    'unit_cost': item.lastPurchaseCost,
                  },
                ],
              );
      if (!mounted) return;
      ref.applyMutation(Mutation.createDraftPurchaseOrders);
      if (ids.isEmpty) {
        AppSnackbar.error(context, 'Could not create the draft order.');
        return;
      }
      context.go('/purchasing/orders/${ids.first}');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busyMedicineId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drugStatusProvider);
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canOrder = can(role, Modules.purchaseOrders, PermAction.edit);

    return Scaffold(
      appBar: AppBar(title: const Text('Drug stock status')),
      body: stockState(
        state,
        onRetry: () {
          ref.invalidate(drugStatusProvider);
          ref.invalidate(stockSummaryProvider);
        },
        builder: (items) {
          final query = _query.trim().toLowerCase();
          final visible = items.where((item) {
            final matches = query.isEmpty ||
                item.medicine.name.toLowerCase().contains(query) ||
                item.medicine.sku.toLowerCase().contains(query);
            final matchesFilter = _filter == 'All' ||
                (_filter == 'Low' && item.isLow) ||
                (_filter == 'Out' && item.isOut);
            return matches && matchesFilter;
          }).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Drug stock status',
                  subtitle:
                      'Live available quantity per medicine, lowest first',
                  actions: [
                    IconButton(
                      tooltip: S.refresh,
                      onPressed: () {
                        ref.invalidate(drugStatusProvider);
                        ref.invalidate(stockSummaryProvider);
                        ref.invalidate(lowStockAlertsProvider);
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search medicine or SKU',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in const ['All', 'Low', 'Out'])
                      ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const EmptyState(message: 'No medicines match this filter.')
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth < 600
                          ? 1
                          : constraints.maxWidth < 1000
                              ? 2
                              : 3;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: 214,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _DrugCard(
                              item: visible[index],
                              canOrder: canOrder,
                            ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _DrugCard({required DrugStatusItem item, required bool canOrder}) {
    final tone = item.isOut
        ? AppColors.danger
        : item.isLow
            ? AppColors.warning
            : AppColors.success;
    final progress = (item.availableQty / item.targetLevel).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.medicine.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(item.statusLabel),
                  backgroundColor: tone.withOpacity(0.12),
                  labelStyle: TextStyle(color: tone, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                item.medicine.strength ?? item.medicine.dosageForm,
                item.medicine.unit,
                item.medicine.sku,
              ].whereType<String>().where((v) => v.isNotEmpty).join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${item.availableQty}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text('available • target ${item.targetLevel}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: tone.withOpacity(0.12),
              color: tone,
              minHeight: 7,
            ),
            const Spacer(),
            if (item.isLow || item.isOut)
              Row(
                children: [
                  Expanded(
                    child: ResponsivePrimaryButton(
                      label: 'Order now',
                      icon: Icons.shopping_cart_outlined,
                      loading: _busyMedicineId == item.medicine.id,
                      onPressed:
                          canOrder ? () => _orderNow(item) : null,
                      expand: true,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
