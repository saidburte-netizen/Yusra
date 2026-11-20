import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';

class AdjustmentsScreen extends ConsumerWidget {
  const AdjustmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.stock, PermAction.edit);
    final movements = ref.watch(movementsProvider(
      (medicineId: null, type: null),
    ));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Adjustments',
              subtitle: 'Write-offs, damage and count corrections',
              actions: [
                if (canEdit)
                  PrimaryButton(
                    label: 'New adjustment',
                    icon: Icons.add,
                    width: 170,
                    onPressed: () => _newAdjustment(context, ref),
                  ),
              ],
            ),
            stockState(
              movements,
              onRetry: () => ref.invalidate(movementsProvider(
                (medicineId: null, type: null),
              )),
              builder: (items) {
                final history = items
                    .where((item) => const {
                          'adjustment',
                          'expired_writeoff',
                          'damage',
                          'void_restore',
                          'sale_return',
                        }.contains(item.type))
                    .toList();
                return Expanded(
                  child: DataTablePlus(
                    columns: const ['Date', 'Medicine', 'Type', 'Change', 'Reason'],
                    rows: [
                      for (final movement in history)
                        DataTablePlusRow(
                          cells: [
                            movement.createdAt == null
                                ? '—'
                                : formatDateTime(movement.createdAt!),
                            movement.medicineName ?? '—',
                            movement.type,
                            '${movement.quantityChange}',
                            movement.reason ?? '—',
                          ],
                        ),
                    ],
                    filterChips: const [
                      'adjustment',
                      'expired_writeoff',
                      'damage',
                      'void_restore',
                      'sale_return',
                    ],
                    exportFileName: 'yusra-adjustments.csv',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newAdjustment(BuildContext context, WidgetRef ref) async {
    final batches = await ref.read(inventoryRepositoryProvider).batches(
          branchId: ref.read(branchScopeProvider),
        );
    if (batches.isEmpty) {
      if (context.mounted) {
        AppSnackbar.error(context, 'Add stock before making an adjustment.');
      }
      return;
    }
    if (!context.mounted) return;
    String batchId = batches.first.id;
    String type = 'adjustment';
    final change = TextEditingController(text: '-1');
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var busy = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New adjustment'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppDropdown<String>(
                    label: 'Batch',
                    value: batchId,
                    items: [
                      for (final batch in batches)
                        DropdownMenuItem(
                          value: batch.id,
                          child: Text(
                            '${batch.medicineName ?? ''} — ${batch.batchNo} (${batch.quantity})',
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => batchId = value ?? batchId),
                  ),
                  const SizedBox(height: 12),
                  AppDropdown<String>(
                    label: 'Type',
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'adjustment', child: Text('Count correction')),
                      DropdownMenuItem(
                          value: 'expired_writeoff', child: Text('Expired write-off')),
                      DropdownMenuItem(value: 'damage', child: Text('Damage')),
                    ],
                    onChanged: (value) => setState(() => type = value ?? 'adjustment'),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Change (negative to remove)',
                    controller: change,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    validator: (value) =>
                        (int.tryParse(value ?? '') ?? 0) != 0 ? null : 'Must not be zero',
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Reason',
                    controller: reason,
                    maxLines: 2,
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            PrimaryButton(
              label: 'Apply',
              width: 120,
              loading: busy,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => busy = true);
                try {
                  await ref.read(inventoryRepositoryProvider).adjustStock(
                        batchId: batchId,
                        change: int.parse(change.text),
                        type: type,
                        reason: reason.text.trim(),
                      );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) AppSnackbar.error(context, '$e');
                } finally {
                  if (context.mounted) setState(() => busy = false);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) {
      AppSnackbar.success(context, 'Adjustment saved.');
      ref.invalidate(movementsProvider((medicineId: null, type: null)));
      ref.invalidate(stockSummaryProvider);
      ref.invalidate(batchesProvider(null));
    }
  }
}
