import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/dates.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../../sales/data/sales.dart';
import '../data/customers.dart';
import '../../../core/errors/app_error.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(Customer? customer) async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.customers, PermAction.edit)) {
      AppSnackbar.error(context, 'You cannot edit customers.');
      return;
    }
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final email = TextEditingController(text: customer?.email ?? '');
    final address = TextEditingController(text: customer?.address ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer == null ? 'Add customer' : 'Edit customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Full name',
                controller: name,
                autofocus: true,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Name is required.' : null,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Phone',
                controller: phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              AppTextField(label: 'Email', controller: email),
              const SizedBox(height: 10),
              AppTextField(label: 'Address', controller: address, maxLines: 2),
              const SizedBox(height: 10),
              AppTextField(label: 'Notes', controller: notes, maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text(S.save),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await ref.read(customersRepositoryProvider).save(
        {
          'name': name.text,
          'phone': phone.text,
          'email': email.text,
          'address': address.text,
          'notes': notes.text,
        },
        id: customer?.id,
      );
      ref.invalidate(customersProvider);
      if (mounted) {
        AppSnackbar.success(context,
            customer == null ? 'Customer added.' : 'Customer updated.');
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  Future<void> _setActive(Customer customer) async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.customers, PermAction.edit)) {
      AppSnackbar.error(context, 'Access denied.');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title:
          customer.isActive ? 'Deactivate customer?' : 'Reactivate customer?',
      message:
          '${customer.name} will ${customer.isActive ? 'no longer' : 'again'} '
          'be available for new sales.',
      confirmLabel: customer.isActive ? 'Deactivate' : 'Reactivate',
      danger: customer.isActive,
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(customersRepositoryProvider)
          .setActive(customer.id, !customer.isActive);
      ref.invalidate(customersProvider);
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.customers, PermAction.edit);
    final customers = ref.watch(customersProvider(_query));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Customers',
              subtitle: 'People who buy from the pharmacy',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: 'Add customer',
                      icon: Icons.person_add,
                      width: 150,
                      onPressed: () => _edit(null),
                    ),
                  ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () => ref.invalidate(customersProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            SizedBox(
              width: 340,
              child: AppTextField(
                label: S.search,
                controller: _search,
                prefixIcon: const Icon(Icons.search, size: 20),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: customers.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return EmptyState(
                      message: _query.isEmpty
                          ? 'No customers yet.'
                          : 'No match for "$_query".',
                      icon: Icons.people_outline,
                      actionLabel: canEdit ? 'Add customer' : null,
                      onAction: canEdit ? () => _edit(null) : null,
                    );
                  }
                  return SingleChildScrollView(
                    child: DataTablePlus(
                      columns: const [
                        'Name',
                        'Phone',
                        'Email',
                        'Address',
                        'Status'
                      ],
                      rows: [
                        for (final customer in rows)
                          DataTablePlusRow(
                            cells: [
                              customer.name,
                              customer.phone ?? '—',
                              customer.email ?? '—',
                              customer.address ?? '—',
                              customer.isActive ? 'Active' : 'Inactive',
                            ],
                            actions: [
                              IconButton(
                                tooltip: 'View',
                                icon: const Icon(Icons.visibility_outlined),
                                onPressed: () =>
                                    context.go('/customers/${customer.id}'),
                              ),
                              if (canEdit) ...[
                                IconButton(
                                  tooltip: S.edit,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(customer),
                                ),
                                IconButton(
                                  tooltip: customer.isActive
                                      ? 'Deactivate'
                                      : 'Reactivate',
                                  icon: Icon(customer.isActive
                                      ? Icons.person_off_outlined
                                      : Icons.person_outline),
                                  onPressed: () => _setActive(customer),
                                ),
                              ],
                            ],
                          ),
                      ],
                      searchHint: 'Filter customers…',
                      exportFileName: 'yusra-customers.csv',
                    ),
                  );
                },
                loading: () => const LoadingSkeleton(lines: 4),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(customersProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer detail with lifetime spend and recent sales.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(id));
    final stats = ref.watch(customerStatsProvider(id));
    const salesFilter = (
      from: null,
      to: null,
      cashierId: null,
      status: null,
      method: null,
      invoice: null,
    );
    final sales = ref.watch(salesProvider(salesFilter));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: customer.when(
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: value.name,
                subtitle: [
                  if (value.phone != null) value.phone!,
                  if (value.email != null) value.email!,
                  if (value.address != null) value.address!,
                ].join('  •  '),
                actions: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.go('/customers'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ],
              ),
              stats.when(
                data: (summary) => ResponsiveGrid(
                  minTileWidth: 200,
                  children: [
                    StatCard(
                      title: 'Lifetime spend',
                      value: formatMoney(summary.lifetimeSpend),
                      icon: Icons.payments,
                    ),
                    StatCard(
                      title: 'Purchases',
                      value: '${summary.visits}',
                      icon: Icons.receipt_long,
                    ),
                    StatCard(
                      title: 'Last purchase',
                      value: summary.lastVisit == null
                          ? '—'
                          : formatDate(summary.lastVisit!),
                      icon: Icons.calendar_today_outlined,
                    ),
                    StatCard(
                      title: 'Status',
                      value: value.isActive ? 'Active' : 'Inactive',
                      icon: Icons.person_outline,
                    ),
                  ],
                ),
                loading: () => const LoadingSkeleton(lines: 2),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(customerStatsProvider(id)),
                ),
              ),
              const SizedBox(height: 18),
              Text('Recent purchases',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Expanded(
                child: sales.when(
                  data: (rows) {
                    final mine =
                        rows.where((sale) => sale.customerId == id).toList();
                    return mine.isEmpty
                        ? const EmptyState(
                            message: 'No purchases yet.',
                            icon: Icons.receipt_long)
                        : SingleChildScrollView(
                            child: DataTablePlus(
                              columns: const [
                                'Invoice',
                                'Date',
                                'Total',
                                'Status'
                              ],
                              rows: [
                                for (final sale in mine.take(50))
                                  DataTablePlusRow(cells: [
                                    sale.invoiceNo,
                                    sale.createdAt == null
                                        ? '—'
                                        : formatDateTime(sale.createdAt!),
                                    formatMoney(sale.total),
                                    sale.status,
                                  ]),
                              ],
                            ),
                          );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorState(
                    message: AppErrorMapper.from(error).message,
                    onRetry: () => ref.invalidate(salesProvider(salesFilter)),
                  ),
                ),
              ),
            ],
          ),
          loading: () => const LoadingSkeleton(lines: 4),
          error: (error, _) => ErrorState(
            message: AppErrorMapper.from(error).message,
            onRetry: () => ref.invalidate(customerProvider(id)),
          ),
        ),
      ),
    );
  }
}
