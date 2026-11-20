import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets.dart';
import '../../suppliers/data/suppliers.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/stock_rules.dart';
import '../../../core/errors/app_error.dart';

Widget statusChip(StockStatus status) => StatusBadge(
      StockRules.label(status),
      tone: switch (status) {
        StockStatus.inStock => StatusTone.success,
        StockStatus.low => StatusTone.gold,
        StockStatus.outOfStock => StatusTone.danger,
        StockStatus.expiringSoon => StatusTone.warning,
        StockStatus.expired => StatusTone.danger,
      },
    );

Widget expiryChip(StockBatch batch, int alertDays) => StatusBadge(
      batch.daysLeft < 0
          ? 'Expired ${formatDate(batch.expiryDate)}'
          : '${batch.daysLeft} days left',
      tone: switch (StockRules.expiryTone(batch.daysLeft, alertDays: alertDays)) {
        ExpiryTone.danger => StatusTone.danger,
        ExpiryTone.warning => StatusTone.warning,
        ExpiryTone.gold => StatusTone.gold,
        ExpiryTone.ok => StatusTone.success,
      },
    );

/// Standard loading / error / data switch used by all B screens.
Widget stockState<T>(
  AsyncValue<T> state, {
  required Widget Function(T data) builder,
  VoidCallback? onRetry,
}) =>
    state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorState(message: AppErrorMapper.from(error).message, onRetry: onRetry),
      data: builder,
    );

Future<void> showAddStockDialog(BuildContext context, WidgetRef ref) async {
  final branch = ref.read(branchScopeProvider);
  if (branch == null) {
    AppSnackbar.error(context, 'Choose a branch first.');
    return;
  }
  final formKey = GlobalKey<FormState>();
  final batchNo = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController(text: '0');
  Medicine? medicine;
  DateTime? expiryDate;
  String? supplierId;
  var busy = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add stock'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SearchableSelect<Medicine>(
                    label: 'Medicine',
                    search: (query) => ref
                        .read(inventoryRepositoryProvider)
                        .medicines(query: query),
                    display: (item) => '${item.name} (${item.sku})',
                    value: medicine,
                    onSelected: (value) => setState(() => medicine = value),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Batch number',
                    controller: batchNo,
                    validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DatePickerField(
                    label: 'Expiry date',
                    value: expiryDate,
                    onChanged: (date) => setState(() => expiryDate = date),
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Quantity',
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          validator: (value) =>
                              (int.tryParse(value ?? '') ?? 0) > 0 ? null : 'Must be above zero',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MoneyField(
                          label: 'Unit cost',
                          controller: cost,
                          validator: (value) => (value ?? 0) >= 0 ? null : 'Invalid',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<SupplierOption>>(
                    future: SupplierOption.load(ref),
                    builder: (context, snapshot) => AppDropdown<String?>(
                      label: 'Supplier (optional)',
                      value: supplierId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None')),
                        for (final supplier in snapshot.data ?? const <SupplierOption>[])
                          DropdownMenuItem(value: supplier.id, child: Text(supplier.name)),
                      ],
                      onChanged: (value) => setState(() => supplierId = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            label: 'Add stock',
            width: 140,
            loading: busy,
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (expiryDate == null) {
                AppSnackbar.error(context, 'Choose a future expiry date.');
                return;
              }
              setState(() => busy = true);
              try {
                await ref.read(inventoryRepositoryProvider).addStock(
                      branchId: branch,
                      medicineId: medicine!.id,
                      batchNo: batchNo.text,
                      expiry: expiryDate!,
                      quantity: int.parse(quantity.text),
                      cost: double.tryParse(cost.text.replaceAll(',', '')) ?? 0,
                      supplierId: supplierId,
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
  if (result == true && context.mounted) {
    AppSnackbar.success(context, 'Stock added.');
    ref.invalidate(stockSummaryProvider);
    ref.invalidate(batchesProvider);
    ref.invalidate(lowStockProvider);
    ref.invalidate(expiringBatchesProvider);
    ref.invalidate(movementsProvider);
  }
}

class SupplierOption {
  const SupplierOption({required this.id, required this.name});
  final String id;
  final String name;

  static Future<List<SupplierOption>> load(WidgetRef ref) async {
    try {
      final rows = await ref.read(supplierRepositoryProvider).list();
      return [for (final row in rows) SupplierOption(id: row.id, name: row.name)];
    } catch (_) {
      return const <SupplierOption>[];
    }
  }
}

Future<void> showAdjustStockDialog(
  BuildContext context,
  WidgetRef ref, {
  required StockBatch batch,
}) async {
  final formKey = GlobalKey<FormState>();
  final change = TextEditingController(text: '-1');
  final reason = TextEditingController();
  String type = 'adjustment';
  var busy = false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Adjust ${batch.batchNo}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDropdown<String>(
                  label: 'Reason type',
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'adjustment', child: Text('Count correction')),
                    DropdownMenuItem(value: 'expired_writeoff', child: Text('Expired write-off')),
                    DropdownMenuItem(value: 'damage', child: Text('Damage')),
                  ],
                  onChanged: (value) => setState(() => type = value ?? 'adjustment'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Change (negative to remove)',
                  controller: change,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  validator: (value) => (int.tryParse(value ?? '') ?? 0) != 0 ? null : 'Must not be zero',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Reason',
                  controller: reason,
                  maxLines: 2,
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
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
                      batchId: batch.id,
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
    ref.invalidate(stockSummaryProvider);
    ref.invalidate(batchesProvider);
    ref.invalidate(movementsProvider);
    ref.invalidate(lowStockProvider);
    ref.invalidate(expiringBatchesProvider);
  }
}
