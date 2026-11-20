import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../data/sales.dart';
import '../logic/receipts.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _busy = false;

  Future<void> _reprint() async {
    try {
      final sale = await ref.read(saleProvider(widget.id).future);
      final items = await ref.read(saleItemsProvider(widget.id).future);
      final payments = await ref.read(salePaymentsProvider(widget.id).future);
      final settings = await ref.read(receiptSettingsProvider.future);
      await Receipts.printSale(
        sale: sale,
        items: items,
        payments: payments,
        settings: settings,
        cashierName: sale.cashierName ?? 'Cashier',
        reprint: true,
      );
    } catch (error) {
      if (mounted) AppSnackbar.error(context, error.toString());
    }
  }

  Future<void> _return(Sale sale, List<SaleItem> items) async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.saleReturns, PermAction.edit)) {
      AppSnackbar.error(context, 'Only a pharmacist or admin can process returns.');
      return;
    }
    final selectable = items.where((item) => item.remaining > 0).toList();
    if (selectable.isEmpty) {
      AppSnackbar.error(context, 'Everything on this invoice has already been returned.');
      return;
    }
    final reason = TextEditingController();
    final method = ValueNotifier<String>('cash');
    final quantities = <String, int>{for (final item in selectable) item.id: 0};
    final restock = <String, bool>{for (final item in selectable) item.id: true};

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Return invoice ${sale.invoiceNo}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select quantities to return. Whole units only.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  ...selectable.map((item) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.medicineName),
                                    Text('Sold ${item.quantity}  •  Returnable ${item.remaining}  •  '
                                        '${formatMoney(item.unitPrice)}',
                                        style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: restock[item.id],
                                onChanged: (value) => setState(
                                    () => restock[item.id] = value ?? true),
                              ),
                              const Text('Restock'),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 72,
                                child: TextFormField(
                                  initialValue: '0',
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Qty', isDense: true),
                                  onChanged: (value) => quantities[item.id] =
                                      int.tryParse(value) ?? 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: method,
                    builder: (context, value, _) => DropdownButtonFormField<String>(
                      value: value,
                      decoration: const InputDecoration(
                          labelText: 'Refund method', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                      ],
                      onChanged: (value) => setState(
                          () => method.value = value ?? 'cash'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppTextField(label: 'Reason', controller: reason),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(S.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (reason.text.trim().isEmpty) return;
                if (quantities.values.every((qty) => qty <= 0)) return;
                Navigator.pop(context, true);
              },
              child: const Text('Process return'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;

    final payload = <Map<String, dynamic>>[];
    for (final item in selectable) {
      final qty = quantities[item.id] ?? 0;
      if (qty <= 0) continue;
      if (qty > item.remaining) {
        AppSnackbar.error(context, 'Return quantity exceeds what is left for ${item.medicineName}.');
        return;
      }
      payload.add({
        'sale_item_id': item.id,
        'quantity': qty,
        'restock': restock[item.id] ?? true,
      });
    }
    setState(() => _busy = true);
    try {
      final returnId = await ref.read(salesRepositoryProvider).processReturn(
            saleId: sale.id,
            items: payload,
            reason: reason.text.trim(),
            refundMethod: method.value,
          );
      ref.invalidate(saleProvider);
      ref.invalidate(saleItemsProvider);
      ref.invalidate(salesProvider);
      ref.invalidate(saleReturnsProvider);
      final settings = await ref.read(receiptSettingsProvider.future);
      await Receipts.printReturnNote(
        returnNo: returnId.substring(0, 8).toUpperCase(),
        invoiceNo: sale.invoiceNo,
        createdAt: DateTime.now(),
        reason: reason.text.trim(),
        refundMethod: method.value,
        amount: payload.fold<double>(
          0,
          (sum, entry) {
            final item = selectable.firstWhere((row) => row.id == entry['sale_item_id']);
            return sum + item.unitPrice * (entry['quantity'] as int);
          },
        ),
        settings: settings,
      );
      if (mounted) AppSnackbar.success(context, 'Return processed.');
    } catch (error) {
      if (mounted) AppSnackbar.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = ref.watch(saleProvider(widget.id));
    final items = ref.watch(saleItemsProvider(widget.id));
    final payments = ref.watch(salePaymentsProvider(widget.id));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: sale.when(
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Invoice ${value.invoiceNo}',
                subtitle: value.createdAt == null
                    ? null
                    : formatDateTime(value.createdAt!),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SecondaryButton(
                      label: 'Back',
                      icon: Icons.arrow_back,
                      width: 100,
                      onPressed: () => context.go('/sales'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reprint',
                    onPressed: _reprint,
                    icon: const Icon(Icons.print_outlined),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  StatCard(
                    title: 'Total',
                    value: formatMoney(value.total),
                    icon: Icons.payments,
                  ),
                  StatCard(
                    title: 'Paid',
                    value: formatMoney(value.paid),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  StatCard(
                    title: 'Change',
                    value: formatMoney(value.changeDue),
                    icon: Icons.redeem_outlined,
                  ),
                  StatCard(
                    title: 'Status',
                    value: value.status.toUpperCase(),
                    icon: Icons.verified_outlined,
                    color: value.status == 'completed'
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      items.when(
                        data: (rows) => DataTablePlus(
                          columns: const [
                            'Medicine', 'Batch', 'Expiry', 'Qty', 'Returned', 'Price', 'Total',
                          ],
                          rows: [
                            for (final item in rows)
                              DataTablePlusRow(cells: [
                                item.medicineName,
                                item.batchNo ?? '—',
                                item.expiryDate == null ? '—' : formatDate(item.expiryDate!),
                                '${item.quantity}',
                                '${item.returnedQty}',
                                formatMoney(item.unitPrice),
                                formatMoney(item.lineTotal),
                              ]),
                          ],
                        ),
                        loading: () => const LoadingSkeleton(lines: 3),
                        error: (error, _) => ErrorState(message: error.toString()),
                      ),
                      const SizedBox(height: 18),
                      Text('Payments', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      payments.when(
                        data: (rows) => DataTablePlus(
                          columns: const ['Method', 'Reference', 'Amount'],
                          rows: [
                            for (final payment in rows)
                              DataTablePlusRow(cells: [
                                payment.method.replaceAll('_', ' '),
                                payment.reference ?? '—',
                                formatMoney(payment.amount),
                              ]),
                          ],
                        ),
                        loading: () => const LoadingSkeleton(lines: 2),
                        error: (error, _) => ErrorState(message: error.toString()),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (value.status == 'completed')
                            PrimaryButton(
                              label: _busy ? 'Working…' : 'Process return',
                              icon: Icons.assignment_return,
                              width: 180,
                              loading: _busy,
                              onPressed: () => _return(value, items.valueOrNull ?? const []),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          loading: () => const LoadingSkeleton(lines: 5),
          error: (error, _) => ErrorState(message: error.toString()),
        ),
      ),
    );
  }
}
