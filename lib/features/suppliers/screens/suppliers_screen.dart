import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../../purchasing/data/purchasing.dart';
import '../data/suppliers.dart';
import '../../../core/errors/app_error.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

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
                    icon: Icons.add,
                    width: 160,
                    onPressed: () => _edit(null),
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
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(suppliersProvider(_query)),
                ),
                data: (items) => DataTablePlus(
                  columns: const [
                    'Name',
                    'Contact',
                    'Phone',
                    'Email',
                    'TIN',
                    'Status',
                    '',
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
                          '',
                        ],
                        actions: [
                          IconButton(
                            tooltip: 'Orders',
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            onPressed: () =>
                                context.go('/suppliers/${item.id}'),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _edit(item),
                            ),
                          if (canEdit)
                            IconButton(
                              tooltip:
                                  item.isActive ? 'Deactivate' : 'Reactivate',
                              icon: Icon(
                                item.isActive
                                    ? Icons.block_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              onPressed: () => _toggle(item),
                            ),
                        ],
                      ),
                  ],
                  exportFileName: 'yusra-suppliers.csv',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Supplier? item) async {
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
                          child:
                              AppTextField(label: 'Phone', controller: phone)),
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
    if (saved != true) return;
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
      if (!mounted) return;
      AppSnackbar.success(context, 'Supplier saved.');
      ref.invalidate(suppliersProvider);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _toggle(Supplier item) async {
    final confirm = await showConfirmDialog(
      context,
      title: item.isActive ? 'Deactivate supplier' : 'Reactivate supplier',
      message: '${item.name} will ${item.isActive ? 'no longer' : 'again'} be '
          'available for new orders.',
    );
    if (confirm != true) return;
    try {
      await ref
          .read(supplierRepositoryProvider)
          .setActive(item.id, !item.isActive);
      if (!mounted) return;
      AppSnackbar.success(context,
          item.isActive ? 'Supplier deactivated.' : 'Supplier reactivated.');
      ref.invalidate(suppliersProvider);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}

/// B10 — supplier page showing its purchase orders.
class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider(''));
    final orders = ref.watch(purchaseOrdersProvider);
    final supplier =
        suppliers.value?.where((item) => item.id == supplierId).firstOrNull;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: supplier?.name ?? 'Supplier',
              subtitle: supplier == null
                  ? null
                  : '${supplier.contactPerson ?? '—'}  •  ${supplier.phone ?? '—'}  •  ${supplier.email ?? '—'}',
            ),
            if (supplier?.address != null || supplier?.paymentTerms != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${supplier?.address ?? ''}   ${supplier?.paymentTerms ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: orders.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    ErrorState(message: AppErrorMapper.from(error).message),
                data: (all) {
                  final items = all
                      .where((order) => order.supplierId == supplierId)
                      .toList();
                  return DataTablePlus(
                    columns: const [
                      'PO number',
                      'Date',
                      'Expected',
                      'Status',
                      'Total',
                      '',
                    ],
                    rows: [
                      for (final order in items)
                        DataTablePlusRow(
                          cells: [
                            order.poNo,
                            order.orderDate == null
                                ? '—'
                                : formatDate(order.orderDate!),
                            order.expectedDate == null
                                ? '—'
                                : formatDate(order.expectedDate!),
                            order.status,
                            formatMoney(order.total),
                            '',
                          ],
                          actions: [
                            IconButton(
                              tooltip: 'Open',
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onPressed: () =>
                                  context.go('/purchasing/orders/${order.id}'),
                            ),
                          ],
                        ),
                    ],
                    exportFileName: 'yusra-supplier-orders.csv',
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
