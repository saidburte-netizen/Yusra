import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';

class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});

  final String medicineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicineState = ref.watch(
      medicinesProvider((query: '', categoryId: null)),
    );
    final batches = ref.watch(batchesProvider(medicineId));
    final movements = ref.watch(movementsProvider(
      (medicineId: medicineId, type: null),
    ));
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.stock, PermAction.edit);
    final medicine =
        medicineState.value?.where((item) => item.id == medicineId).firstOrNull;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: medicine?.name ?? 'Medicine',
              subtitle: medicine == null
                  ? null
                  : '${medicine.sku}  •  ${medicine.genericName ?? '—'}',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SecondaryButton(
                      label: 'Adjust',
                      width: 110,
                      onPressed: () {
                        final first = batches.value?.firstOrNull;
                        if (first == null) {
                          AppSnackbar.error(context, 'No batch to adjust.');
                          return;
                        }
                        showAdjustStockDialog(context, ref, batch: first);
                      },
                    ),
                  ),
                if (canEdit)
                  PrimaryButton(
                    label: 'Add stock',
                    icon: Icons.add,
                    width: 130,
                    onPressed: () => showAddStockDialog(context, ref),
                  ),
              ],
            ),
            if (medicineState.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (medicine == null)
              const ErrorState(message: 'Medicine not found.')
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ResponsiveGrid(
                        minTileWidth: 200,
                        children: [
                          StatCard(
                            title: 'Selling price',
                            value: formatMoney(medicine.sellingPrice),
                            icon: Icons.sell_outlined,
                            color: AppColors.pink600,
                          ),
                          if (role != AppRole.cashier)
                            StatCard(
                              title: 'Cost price',
                              value: formatMoney(medicine.costPrice),
                              icon: Icons.price_change_outlined,
                              color: AppColors.gold700,
                            ),
                          StatCard(
                            title: 'Reorder level',
                            value: '${medicine.reorderLevel}',
                            icon: Icons.notifications_active_outlined,
                            color: AppColors.warning,
                          ),
                          StatCard(
                            title: 'Batches',
                            value: '${batches.value?.length ?? 0}',
                            icon: Icons.inventory_2_outlined,
                            color: AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Batches',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      stockState(
                        batches,
                        builder: (items) => DataTablePlus(
                          columns: const [
                            'Batch',
                            'Expiry',
                            'Quantity',
                            'Cost',
                            'Status',
                            ''
                          ],
                          rows: [
                            for (final batch in items)
                              DataTablePlusRow(
                                cells: [
                                  batch.batchNo,
                                  formatDate(batch.expiryDate),
                                  '${batch.quantity}',
                                  formatMoney(batch.costPrice),
                                  batch.daysLeft < 0
                                      ? 'Expired'
                                      : '${batch.daysLeft} days',
                                  '',
                                ],
                                actions: [
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
                          exportFileName: 'yusra-batches.csv',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Movement history',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      stockState(
                        movements,
                        builder: (items) => DataTablePlus(
                          columns: const ['Date', 'Type', 'Change', 'Reason'],
                          rows: [
                            for (final movement in items)
                              DataTablePlusRow(
                                cells: [
                                  movement.createdAt == null
                                      ? '—'
                                      : formatDateTime(movement.createdAt!),
                                  movement.type,
                                  '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange}',
                                  movement.reason ?? '—',
                                ],
                              ),
                          ],
                          exportFileName: 'yusra-movements.csv',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => context.go('/inventory/alerts'),
                          icon: const Icon(Icons.warning_amber_outlined),
                          label: const Text('View stock alerts'),
                        ),
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
