import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../data/purchasing.dart';
import '../../../core/errors/app_error.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  String? _status;

  static const statuses = [
    'draft',
    'ordered',
    'partially_received',
    'received',
    'cancelled',
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseOrdersProvider);
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.purchaseOrders, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Purchase orders',
              subtitle: 'Drafts, approvals and goods receiving',
              actions: [
                if (canEdit)
                  PrimaryButton(
                    label: 'New order',
                    icon: Icons.add,
                    width: 140,
                    onPressed: () => context.go('/purchasing/orders/new'),
                  ),
              ],
            ),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                for (final status in statuses)
                  FilterChip(
                    label: Text(status.replaceAll('_', ' ')),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(purchaseOrdersProvider),
                ),
                data: (orders) {
                  final visible = orders
                      .where((order) =>
                          _status == null || order.status == _status)
                      .toList();
                  return DataTablePlus(
                    columns: const [
                      'PO number',
                      'Supplier',
                      'Order date',
                      'Expected',
                      'Total',
                      'Status',
                      '',
                    ],
                    rows: [
                      for (final order in visible)
                        DataTablePlusRow(
                          cells: [
                            order.poNo,
                            order.supplierId.substring(
                              0,
                              order.supplierId.length.clamp(0, 8),
                            ),
                            order.orderDate == null
                                ? '—'
                                : formatDate(order.orderDate!),
                            order.expectedDate == null
                                ? '—'
                                : formatDate(order.expectedDate!),
                            formatMoney(order.total),
                            order.status.replaceAll('_', ' '),
                            '',
                          ],
                          actions: [
                            StatusBadge(
                              order.status.replaceAll('_', ' '),
                              tone: switch (order.status) {
                                'draft' => StatusTone.neutral,
                                'ordered' => StatusTone.gold,
                                'partially_received' => StatusTone.warning,
                                'received' => StatusTone.success,
                                'cancelled' => StatusTone.danger,
                                _ => StatusTone.neutral,
                              },
                            ),
                            IconButton(
                              tooltip: 'Open',
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onPressed: () =>
                                  context.go('/purchasing/orders/${order.id}'),
                            ),
                          ],
                        ),
                    ],
                    exportFileName: 'yusra-purchase-orders.csv',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
