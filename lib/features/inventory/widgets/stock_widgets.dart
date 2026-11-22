import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets.dart';
import '../../suppliers/data/suppliers.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/stock_rules.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../data/inventory_ids.dart';
import '../screens/medicines_screen.dart' show showMedicineFormDialog;
import 'responsive_ui.dart';

/// Dialog content width that never exceeds a phone viewport. A fixed 480/520
/// pixel dialog overflows at 360x640, so every stock dialog sizes from the
/// available screen width instead.
double dialogContentWidth(BuildContext context, {double maxWidth = 520}) {
  final available = MediaQuery.sizeOf(context).width - 48;
  if (available < 240) return 240;
  return available > maxWidth ? maxWidth : available;
}

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
      tone: switch (
          StockRules.expiryTone(batch.daysLeft, alertDays: alertDays)) {
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
      error: (error, _) => ErrorState(
          message: AppErrorMapper.from(error).message, onRetry: onRetry),
      data: builder,
    );

/// Registers a brand-new medicine from the shared catalogue dialog and returns
/// the saved row so pickers can select it immediately.
Future<Medicine?> addNewMedicine(BuildContext context, WidgetRef ref) async {
  final data = await showMedicineFormDialog(context, ref);
  if (data == null) return null;
  final payload = Map<String, dynamic>.from(data);
  final rawId = payload['id'];
  final id =
      rawId is String && rawId.trim().isNotEmpty ? rawId : generateUuidV4();
  payload['id'] = id;
  final repository = ref.read(inventoryRepositoryProvider);
  await repository.saveMedicine(payload);
  return repository.medicine(id);
}

/// Shared display string for medicine pickers: name, SKU and barcode.
String medicineOptionLabel(Medicine item) {
  final barcode = item.barcode?.trim() ?? '';
  return barcode.isEmpty
      ? '${item.name} (${item.sku})'
      : '${item.name} (${item.sku}) • $barcode';
}

Future<void> showAddStockDialog(BuildContext context, WidgetRef ref) async {
  final branch = ref.read(branchScopeProvider);
  if (branch == null) {
    AppSnackbar.error(context, S.chooseBranchFirst);
    return;
  }
  final formKey = GlobalKey<FormState>();
  final batchNo = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  Medicine? medicine;
  DateTime? expiryDate;
  String? supplierId;
  var source = 'opening';
  var busy = false;
  String? successMessage;

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Add stock'),
        content: SizedBox(
          width: dialogContentWidth(dialogContext),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchableSelect<Medicine>(
                    label: 'Medicine',
                    search: (query) =>
                        ref.read(inventoryRepositoryProvider).medicines(
                              query: query,
                              limit: query.trim().isEmpty ? 20 : 200,
                            ),
                    display: medicineOptionLabel,
                    value: medicine,
                    onSelected: (value) => setState(() => medicine = value),
                    onAddNew: (pickerContext) =>
                        addNewMedicine(pickerContext, ref),
                    validator: (value) => value == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  AppDropdown<String>(
                    label: 'Stock source',
                    value: source,
                    items: const [
                      DropdownMenuItem(
                        value: 'opening',
                        child: Text('Opening stock (already in store)'),
                      ),
                      DropdownMenuItem(
                        value: 'purchase',
                        child: Text('Purchase received'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(
                            'Other (donation, transfer, return from customer)'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => source = value ?? 'opening'),
                  ),
                  if (source == 'purchase') ...[
                    const SizedBox(height: 12),
                    FutureBuilder<List<SupplierOption>>(
                      future: SupplierOption.load(ref),
                      builder: (context, snapshot) => AppDropdown<String?>(
                        label: 'Supplier (optional)',
                        value: supplierId,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          for (final supplier
                              in snapshot.data ?? const <SupplierOption>[])
                            DropdownMenuItem(
                                value: supplier.id, child: Text(supplier.name)),
                        ],
                        onChanged: (value) =>
                            setState(() => supplierId = value),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Batch number (optional)',
                    controller: batchNo,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to generate OPEN-YYYYMMDD-NNN',
                    style:
                        Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                  ),
                  const SizedBox(height: 12),
                  DatePickerField(
                    label: 'Expiry date',
                    value: expiryDate,
                    onChanged: (date) => setState(() => expiryDate = date),
                    emptyText: 'Select expiry date',
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Quantity',
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                        ? null
                        : 'Must be above zero',
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Unit cost (optional)',
                    controller: cost,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final parsed =
                          double.tryParse((value ?? '').replaceAll(',', ''));
                      return parsed == null || parsed >= 0
                          ? null
                          : 'Must not be negative';
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ResponsivePrimaryButton(
            label: 'Add stock',
            loading: busy,
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              if (expiryDate == null) {
                AppSnackbar.error(
                    dialogContext, 'Choose a future expiry date.');
                return;
              }
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final expiryDay = DateTime(
                  expiryDate!.year, expiryDate!.month, expiryDate!.day);
              if (!expiryDay.isAfter(today)) {
                AppSnackbar.error(dialogContext,
                    'Expired stock cannot be added; use write-off.');
                return;
              }
              final count = int.parse(quantity.text);
              setState(() => busy = true);
              try {
                final savedBatch = await ref
                    .read(inventoryRepositoryProvider)
                    .addStock(
                      branchId: branch,
                      medicineId: medicine!.id,
                      batchNo: batchNo.text.trim(),
                      expiry: expiryDate!,
                      quantity: count,
                      cost: double.tryParse(cost.text.replaceAll(',', '')) ?? 0,
                      source: source,
                      supplierId: source == 'purchase' ? supplierId : null,
                    );
                successMessage =
                    'Added $count × ${medicine!.name} (batch $savedBatch).';
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) {
                if (dialogContext.mounted) {
                  AppSnackbar.error(
                      dialogContext, AppErrorMapper.from(e).message);
                }
              } finally {
                if (dialogContext.mounted) setState(() => busy = false);
              }
            },
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    AppSnackbar.success(context, successMessage ?? 'Stock added.');
    invalidateStockProviders(ref);
  }
}

/// Every provider that can change when a stock batch is written.
void invalidateStockProviders(WidgetRef ref) {
  ref.invalidate(stockSummaryProvider);
  ref.invalidate(batchesProvider);
  ref.invalidate(lowStockProvider);
  ref.invalidate(expiringBatchesProvider);
  ref.invalidate(movementsProvider);
  ref.invalidate(reorderSuggestionsProvider);
}

class SupplierOption {
  const SupplierOption({required this.id, required this.name});
  final String id;
  final String name;

  static Future<List<SupplierOption>> load(WidgetRef ref) async {
    try {
      final rows = await ref.read(supplierRepositoryProvider).list();
      return [
        for (final row in rows) SupplierOption(id: row.id, name: row.name)
      ];
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
          width: dialogContentWidth(context),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDropdown<String>(
                  label: 'Reason type',
                  value: type,
                  items: const [
                    DropdownMenuItem(
                        value: 'adjustment', child: Text('Count correction')),
                    DropdownMenuItem(
                        value: 'expired_writeoff',
                        child: Text('Expired write-off')),
                    DropdownMenuItem(value: 'damage', child: Text('Damage')),
                  ],
                  onChanged: (value) =>
                      setState(() => type = value ?? 'adjustment'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Change (negative to remove)',
                  controller: change,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  validator: (value) => (int.tryParse(value ?? '') ?? 0) != 0
                      ? null
                      : 'Must not be zero',
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
          ResponsivePrimaryButton(
            label: 'Apply',
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
                if (context.mounted) {
                  AppSnackbar.error(context, AppErrorMapper.from(e).message);
                }
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
