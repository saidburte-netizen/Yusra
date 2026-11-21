import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../../sales/logic/cart.dart';

const _methods = [
  ('cash', 'Cash', Icons.money),
  ('mobile_money', 'Mobile money', Icons.phone_android),
  ('card', 'Card', Icons.credit_card),
  ('bank_transfer', 'Bank transfer', Icons.account_balance),
];

/// Returns the payments to send to create_sale. Split payments are allowed;
/// only cash may produce change (the RPC enforces the same rule).
Future<List<CartPayment>?> showPaymentDialog(
  BuildContext context, {
  required double total,
}) {
  final rows = <_PaymentRow>[_PaymentRow(method: 'cash', amount: total)];
  final quick = quickCashAmounts(total);

  return showDialog<List<CartPayment>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final paid = paidTotal(rows.map((row) => row.toPayment()).toList());
        final change = changeDue(
            total: total,
            payments: rows.map((row) => row.toPayment()).toList());
        final hasCash = rows.any((row) => row.method == 'cash');
        final canSubmit =
            rows.isNotEmpty && paid >= total && (paid == total || hasCash);

        return AlertDialog(
          title: Text('Payment  •  ${formatMoney(total)}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Quick cash',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final amount in quick)
                        ActionChip(
                          label: Text(formatMoney(amount)),
                          onPressed: () => setState(() {
                            rows.removeWhere((row) => row.method == 'cash');
                            rows.insert(
                              0,
                              _PaymentRow(method: 'cash', amount: amount),
                            );
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...rows.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                value: row.method,
                                isDense: true,
                                decoration: const InputDecoration(
                                    labelText: 'Method', isDense: true),
                                items: [
                                  for (final method in _methods)
                                    DropdownMenuItem(
                                      value: method.$1,
                                      child: Text(method.$2),
                                    ),
                                ],
                                onChanged: (value) => setState(
                                    () => row.method = value ?? 'cash'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: AppTextField(
                                label: 'Amount',
                                controller: row.amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: rows.length == 1
                                  ? null
                                  : () => setState(() => rows.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add another payment'),
                    onPressed: () => setState(
                        () => rows.add(_PaymentRow(method: 'card', amount: 0))),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Paid'),
                      Text(formatMoney(paid),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change'),
                      Text(formatMoney(change),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: change > 0 ? AppColors.success : null,
                          )),
                    ],
                  ),
                  if (!canSubmit && paid > total && !hasCash)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Add a cash payment to give change.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(S.cancel),
            ),
            ElevatedButton(
              onPressed: canSubmit
                  ? () => Navigator.pop(
                        context,
                        rows.map((row) => row.toPayment()).toList(),
                      )
                  : null,
              child: Text('Confirm  ${formatMoney(total)}'),
            ),
          ],
        );
      },
    ),
  );
}

class _PaymentRow {
  _PaymentRow({
    required this.method,
    required double amount,
  }) : amountController = TextEditingController(
          text: amount == 0 ? '' : amount.toStringAsFixed(2),
        );

  String method;
  final TextEditingController amountController;

  CartPayment toPayment() => CartPayment(
        method: method,
        amount: double.tryParse(amountController.text.replaceAll(',', '')) ?? 0,
      );
}
