import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets.dart';
import '../../purchasing/data/purchasing.dart';
import '../data/suppliers.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key, this.initialSuppliers});

  /// Optional preloaded rows keep this screen pumpable in widget tests.
  final List<Supplier>? initialSuppliers;

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(suppliersProvider(_query));
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.suppliers, PermAction.edit);
    final items = widget.initialSuppliers ??
        state.maybeWhen(
          data: (value) => value,
          orElse: () => const <Supplier>[],
        ) ??
        const <Supplier>[];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Suppliers',
              subtitle: 'Vendors, contacts and payment terms',
              actions: [
                if (canEdit)
                  PrimaryButton(
                    label: 'New supplier',
                    width: 160,
                    onPressed: () => editSupplier(context, ref, null),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(suppliersProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            SizedBox(
              width: 320,
              child: AppTextField(
                label: 'Search name, contact or phone',
                controller: _search,
                prefixIcon: const Icon(Icons.search, size: 20),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: widget.initialSuppliers == null && state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : widget.initialSuppliers == null && state.hasError
                      ? ErrorState(
                          message: AppErrorMapper.from(
                                  state.error ?? 'Failed to load suppliers')
                              .message,
                          onRetry: () =>
                              ref.invalidate(suppliersProvider(_query)),
                        )
                      : items.isEmpty
                          ? EmptyState(
                              message: _query.isEmpty
                                  ? 'No suppliers yet.'
                                  : 'No match for "$_query".',
                              icon: Icons.local_shipping_outlined,
                              actionLabel: canEdit ? 'New supplier' : null,
                              onAction: canEdit
                                  ? () => editSupplier(context, ref, null)
                                  : null,
                            )
                          : DataTablePlus(
                              columns: const [
                                'Name',
                                'Contact',
                                'Phone',
                                'Email',
                                'TIN',
                                'Status',
                              ],
                              rows: [
                                for (final item in items)
                                  DataTablePlusRow(
                                    cells: [
                                      item.name,
                                      item.contactPerson ?? '—',
                                      item.phone ?? '—',
                                      item.email ?? '—',
                                      item.tin ?? '—',
                                      item.isActive ? 'Active' : 'Inactive',
                                    ],
                                    actions: [
                                      RowActions(actions: [
                                        RowAction(
                                          label: 'View',
                                          icon: Icons.receipt_long_outlined,
                                          onSelected: () async {
                                            context.go('/suppliers/${item.id}');
                                            return null;
                                          },
                                        ),
                                        RowAction(
                                          label: 'Edit',
                                          icon: Icons.edit_outlined,
                                          allowed: canEdit,
                                          onSelected: () async {
                                            await editSupplier(context, ref, item);
                                            return null;
                                          },
                                          mutation: Mutation.saveSupplier,
                                        ),
                                        RowAction(
                                          label: item.isActive
                                              ? 'Deactivate'
                                              : 'Reactivate',
                                          icon: item.isActive
                                              ? Icons.block_outlined
                                              : Icons.check_circle_outline,
                                          allowed: canEdit,
                                          confirmTitle: item.isActive
                                              ? 'Deactivate supplier'
                                              : 'Reactivate supplier',
                                          confirmMessage:
                                              '${item.name} will ${item.isActive ? 'no longer' : 'again'} be available for new orders.',
                                          onSelected: () =>
                                              _rowSetActive(ref, item),
                                          mutation: Mutation.saveSupplier,
                                        ),
                                        RowAction(
                                          label: 'Delete',
                                          icon: Icons.delete_outline,
                                          allowed: canEdit,
                                          danger: true,
                                          confirmTitle: 'Delete supplier',
                                          confirmMessage:
                                              'Delete ${item.name}? Suppliers with purchase orders cannot be deleted.',
                                          onSelected: () => _deleteSupplier(ref, item),
                                          mutation: Mutation.saveSupplier,
                                        ),
                                      ]),
                                    ],
                                  ),
                              ],
                              exportFileName: 'yusra-suppliers.csv',
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _rowSetActive(WidgetRef ref, Supplier item) async {
  final active = !item.isActive;
  await ref.read(supplierRepositoryProvider).setActive(item.id, active);
  ref.invalidate(suppliersProvider);
  ref.invalidate(supplierProvider(item.id));
  return active ? 'Supplier reactivated.' : 'Supplier deactivated.';
}

/// Suppliers referenced by purchase orders are in use and cannot be deleted.
Future<String?> _deleteSupplier(WidgetRef ref, Supplier item) async {
  final rows = await SupabaseService.client
      .from('purchase_orders')
      .select('id')
      .eq('supplier_id', item.id)
      .limit(1);
  if ((rows as List).isNotEmpty) {
    throw AppError(
        'This supplier has purchase orders. Deactivate it instead.');
  }
  await SupabaseService.client.from('suppliers').delete().eq('id', item.id);
  ref.invalidate(suppliersProvider);
  return 'Supplier deleted.';
}

/// Shared create/edit entry point for the list and the detail screen.
Future<void> editSupplier(
  BuildContext context,
  WidgetRef ref,
  Supplier? item,
) async {
  final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
  if (!can(role, Modules.suppliers, PermAction.edit)) {
    AppSnackbar.error(context, 'You do not have permission to edit suppliers.');
    return;
  }
  final name = TextEditingController(text: item?.name ?? '');
  final contact = TextEditingController(text: item?.contactPerson ?? '');
  final phone = TextEditingController(text: item?.phone ?? '');
  final email = TextEditingController(text: item?.email ?? '');
  final address = TextEditingController(text: item?.address ?? '');
  final tin = TextEditingController(text: item?.tin ?? '');
  final terms = TextEditingController(text: item?.paymentTerms ?? '');
  final notes = TextEditingController(text: item?.notes ?? '');
  final formKey = GlobalKey<FormState>();
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(item == null ? 'New supplier' : 'Edit supplier'),
      content: SizedBox(
        width: 500,
        height: 590,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: name,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                AppTextField(label: 'Contact person', controller: contact),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: AppTextField(label: 'Phone', controller: phone)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                        label: 'Email',
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          return text.contains('@') ? null : 'Invalid email';
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(
                    label: 'Address', controller: address, maxLines: 2),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: AppTextField(label: 'TIN', controller: tin)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                          label: 'Payment terms', controller: terms),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(label: 'Notes', controller: notes, maxLines: 3),
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
          label: 'Save',
          width: 110,
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
        ),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  try {
    await ref.read(supplierRepositoryProvider).save(
      {
        'name': name.text.trim(),
        'contact_person':
            contact.text.trim().isEmpty ? null : contact.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'email': email.text.trim().isEmpty ? null : email.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'tin': tin.text.trim().isEmpty ? null : tin.text.trim(),
        'payment_terms': terms.text.trim().isEmpty ? null : terms.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      },
      id: item?.id,
    );
    ref.invalidate(suppliersProvider);
    if (item != null) ref.invalidate(supplierProvider(item.id));
    if (context.mounted) {
      AppSnackbar.success(
          context, item == null ? 'Supplier created.' : 'Supplier updated.');
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}

/// Suppliers keep purchase-order history, so delete is n/a by design —
/// deactivate instead. This helper is the only status-change entry point.
Future<void> setSupplierActive(
  BuildContext context,
  WidgetRef ref,
  Supplier item, {
  VoidCallback? onDone,
}) async {
  final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
  if (!can(role, Modules.suppliers, PermAction.edit)) {
    AppSnackbar.error(context, 'You do not have permission to edit suppliers.');
    return;
  }
  final confirm = await showConfirmDialog(
    context,
    title: item.isActive ? 'Deactivate supplier' : 'Reactivate supplier',
    message: '${item.name} will ${item.isActive ? 'no longer' : 'again'} be '
        'available for new orders.',
  );
  if (confirm != true || !context.mounted) return;
  final active = !item.isActive;
  try {
    await ref.read(supplierRepositoryProvider).setActive(item.id, active);
    ref.invalidate(suppliersProvider);
    ref.invalidate(supplierProvider(item.id));
    onDone?.call();
    if (context.mounted) {
      AppSnackbar.success(
        context,
        active ? 'Supplier reactivated.' : 'Supplier deactivated.',
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}

/// B10 — supplier page showing its purchase orders.
class SupplierDetailScreen extends ConsumerStatefulWidget {
  const SupplierDetailScreen({
    super.key,
    required this.supplierId,
    this.initialSupplier,
    this.initialOrders,
  });

  final String supplierId;
  final Supplier? initialSupplier;
  final List<PurchaseOrder>? initialOrders;

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen> {
  bool _busy = false;

  Future<void> _edit(Supplier value) async {
    setState(() => _busy = true);
    await editSupplier(context, ref, value);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(Supplier value) async {
    setState(() => _busy = true);
    await setSupplierActive(context, ref, value);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.suppliers, PermAction.edit);
    final supplierState = ref.watch(supplierProvider(widget.supplierId));
    final supplier = widget.initialSupplier ?? supplierState.valueOrNull;
    final ordersState = ref.watch(purchaseOrdersProvider);
    final orders = widget.initialOrders ?? ordersState.valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: supplier?.name ?? 'Supplier',
                subtitle: supplier == null
                    ? null
                    : '${supplier.contactPerson ?? '—'}  •  '
                        '${supplier.phone ?? '—'}  •  ${supplier.email ?? '—'}',
                actions: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/suppliers'),
                  ),
                  if (canEdit && supplier != null) ...[
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _busy ? null : () => _edit(supplier),
                    ),
                    IconButton(
                      tooltip: supplier.isActive ? 'Deactivate' : 'Reactivate',
                      icon: Icon(supplier.isActive
                          ? Icons.block_outlined
                          : Icons.check_circle_outline),
                      onPressed: _busy ? null : () => _toggle(supplier),
                    ),
                  ],
                  if (canEdit)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PrimaryButton(
                        label: 'New purchase order',
                        width: 190,
                        onPressed: () => context.go('/purchasing/orders/new'),
                      ),
                    ),
                ],
              ),
              if (supplier == null)
                (widget.initialSupplier == null && supplierState.isLoading
                    ? const LoadingSkeleton(lines: 3)
                    : ErrorState(
                        message: AppErrorMapper.from(
                                supplierState.error ?? 'Supplier not found')
                            .message,
                        onRetry: () =>
                            ref.invalidate(supplierProvider(widget.supplierId)),
                      ))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (supplier.address != null ||
                        supplier.paymentTerms != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${supplier.address ?? ''}   '
                          '${supplier.paymentTerms ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Text('Purchase orders',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 380,
                      child: widget.initialOrders == null &&
                              ordersState.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : widget.initialOrders == null && ordersState.hasError
                              ? ErrorState(
                                  message: AppErrorMapper.from(
                                          ordersState.error ?? 'Load failed')
                                      .message,
                                  onRetry: () =>
                                      ref.invalidate(purchaseOrdersProvider),
                                )
                              : orders.isEmpty
                                  ? const EmptyState(
                                      message: 'No purchase orders yet.',
                                      icon: Icons.receipt_long_outlined)
                                  : DataTablePlus(
                                      columns: const [
                                        'PO number',
                                        'Date',
                                        'Expected',
                                        'Status',
                                        'Total',
                                      ],
                                      rows: [
                                        for (final order in orders)
                                          DataTablePlusRow(
                                            cells: [
                                              order.poNo,
                                              order.orderDate == null
                                                  ? '—'
                                                  : formatDate(
                                                      order.orderDate!),
                                              order.expectedDate == null
                                                  ? '—'
                                                  : formatDate(
                                                      order.expectedDate!),
                                              order.status,
                                              formatMoney(order.total),
                                            ],
                                            actions: [
                                              IconButton(
                                                tooltip: 'Open',
                                                icon: const Icon(
                                                    Icons.open_in_new,
                                                    size: 18),
                                                onPressed: () => context.go(
                                                    '/purchasing/orders/${order.id}'),
                                              ),
                                            ],
                                          ),
                                      ],
                                      exportFileName:
                                          'yusra-supplier-orders.csv',
                                    ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
