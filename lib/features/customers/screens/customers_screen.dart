import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/strings.dart';
import '../../../core/widgets.dart';
import '../data/customers.dart';
import '../../sales/data/sales.dart';

/// Customers list. Pass [initialCustomers] to render preloaded rows without
/// waiting for a live Supabase client (used by the layout widget tests).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key, this.initialCustomers});

  final List<Customer>? initialCustomers;

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.customers, PermAction.edit);
    final customers = ref.watch(customersProvider(_query));
    final rows = widget.initialCustomers ??
        customers.maybeWhen(
          data: (value) => value,
          orElse: () => const <Customer>[],
        ) ??
        const <Customer>[];

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
                      width: 150,
                      onPressed: () => editCustomer(context, ref, null),
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
              child: widget.initialCustomers == null && customers.isLoading
                  ? const LoadingSkeleton(lines: 4)
                  : widget.initialCustomers == null && customers.hasError
                      ? ErrorState(
                          message: AppErrorMapper.from(
                                  customers.error ?? 'Failed to load customers')
                              .message,
                          onRetry: () => ref.invalidate(customersProvider),
                        )
                      : rows.isEmpty
                          ? EmptyState(
                              message: _query.isEmpty
                                  ? 'No customers yet.'
                                  : 'No match for "$_query".',
                              icon: Icons.people_outline,
                              actionLabel: canEdit ? 'Add customer' : null,
                              onAction: canEdit
                                  ? () => editCustomer(context, ref, null)
                                  : null,
                            )
                          : SingleChildScrollView(
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
                                        customer.isActive
                                            ? 'Active'
                                            : 'Inactive',
                                      ],
                                      actions: [
                                        IconButton(
                                          tooltip: 'View',
                                          icon: const Icon(
                                              Icons.visibility_outlined),
                                          onPressed: () => context
                                              .go('/customers/${customer.id}'),
                                        ),
                                        if (canEdit) ...[
                                          IconButton(
                                            tooltip: S.edit,
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            onPressed: () => editCustomer(
                                                context, ref, customer),
                                          ),
                                          IconButton(
                                            tooltip: customer.isActive
                                                ? 'Deactivate'
                                                : 'Reactivate',
                                            icon: Icon(customer.isActive
                                                ? Icons.person_off_outlined
                                                : Icons.person_outline),
                                            onPressed: () => setCustomerActive(
                                              context,
                                              ref,
                                              customer,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                                searchHint: 'Filter customers…',
                                exportFileName: 'yusra-customers.csv',
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared create/edit entry point used by the list and the detail screen.
Future<void> editCustomer(
  BuildContext context,
  WidgetRef ref,
  Customer? customer,
) async {
  final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
  if (!can(role, Modules.customers, PermAction.edit)) {
    AppSnackbar.error(context, S.forbidden);
    return;
  }
  final values = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _CustomerDialog(customer: customer),
  );
  if (values == null || !context.mounted) return;
  try {
    await ref.read(customersRepositoryProvider).save(values, id: customer?.id);
    ref.invalidate(customersProvider);
    if (customer != null) ref.invalidate(customerProvider(customer.id));
    if (context.mounted) {
      AppSnackbar.success(context,
          customer == null ? 'Customer created.' : 'Customer updated.');
    }
  } catch (error) {
    if (context.mounted) {
      AppSnackbar.error(context, AppErrorMapper.from(error).message);
    }
  }
}

/// Shared deactivate / reactivate entry point. There is no hard delete: the
/// customers table keeps history, so only is_active is toggled.
Future<void> setCustomerActive(
  BuildContext context,
  WidgetRef ref,
  Customer customer, {
  VoidCallback? onDone,
}) async {
  final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
  if (!can(role, Modules.customers, PermAction.edit)) {
    AppSnackbar.error(context, S.forbidden);
    return;
  }
  final active = !customer.isActive;
  try {
    await ref.read(customersRepositoryProvider).setActive(customer.id, active);
    ref.invalidate(customersProvider);
    ref.invalidate(customerProvider(customer.id));
    onDone?.call();
    if (context.mounted) {
      AppSnackbar.success(
        context,
        active ? 'Customer reactivated.' : 'Customer deactivated.',
      );
    }
  } catch (error) {
    if (context.mounted) {
      AppSnackbar.error(context, AppErrorMapper.from(error).message);
    }
  }
}

/// Customer detail with lifetime spend and recent sales.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.id,
    this.initialCustomer,
    this.initialStats,
    this.initialSales,
  });

  final String id;
  final Customer? initialCustomer;
  final CustomerStats? initialStats;
  final List<Sale>? initialSales;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  bool _busy = false;

  Future<void> _edit(Customer value) async {
    setState(() => _busy = true);
    await editCustomer(context, ref, value);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setActive(Customer value) async {
    setState(() => _busy = true);
    await setCustomerActive(context, ref, value);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.customers, PermAction.edit);
    final customer = ref.watch(customerProvider(widget.id));
    final stats = ref.watch(customerStatsProvider(widget.id));
    const salesFilter = (
      from: null,
      to: null,
      cashierId: null,
      status: null,
      method: null,
      invoice: null,
    );
    final sales = ref.watch(salesProvider(salesFilter));
    final detail = widget.initialCustomer == null
        ? customer
        : AsyncData<Customer>(widget.initialCustomer!);
    final statsState = widget.initialStats == null
        ? stats
        : AsyncData<CustomerStats>(widget.initialStats!);
    final salesState = widget.initialSales == null
        ? sales
        : AsyncData<List<Sale>>(widget.initialSales!);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: detail.when(
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
                    if (canEdit) ...[
                      IconButton(
                        tooltip: S.edit,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy ? null : () => _edit(value),
                      ),
                      IconButton(
                        tooltip: value.isActive ? 'Deactivate' : 'Reactivate',
                        icon: Icon(value.isActive
                            ? Icons.person_off_outlined
                            : Icons.person_outline),
                        onPressed: _busy ? null : () => _setActive(value),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                statsState.when(
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
                    onRetry: () =>
                        ref.invalidate(customerStatsProvider(widget.id)),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Recent purchases',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                salesState.when(
                  data: (allSales) {
                    final mine = allSales
                        .where((sale) => sale.customerId == widget.id)
                        .toList();
                    return mine.isEmpty
                        ? const EmptyState(
                            message: 'No purchases yet.',
                            icon: Icons.receipt_long)
                        : DataTablePlus(
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
                          );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorState(
                    message: AppErrorMapper.from(error).message,
                    onRetry: () => ref.invalidate(salesProvider(salesFilter)),
                  ),
                ),
              ],
            ),
            loading: () => const LoadingSkeleton(lines: 4),
            error: (error, _) => ErrorState(
              message: AppErrorMapper.from(error).message,
              onRetry: () => ref.invalidate(customerProvider(widget.id)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer});
  final Customer? customer;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.customer?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.customer?.phone ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.customer?.email ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.customer?.address ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.customer?.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    Navigator.pop<Map<String, dynamic>>(context, {
      'name': _name.text,
      'phone': _phone.text,
      'email': _email.text,
      'address': _address.text,
      'notes': _notes.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Add customer' : S.edit),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Name',
                controller: _name,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? S.required : null,
              ),
              const SizedBox(height: 10),
              AppTextField(label: 'Phone', controller: _phone),
              const SizedBox(height: 10),
              AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              AppTextField(label: 'Address', controller: _address),
              const SizedBox(height: 10),
              AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
        PrimaryButton(
          label: widget.customer == null ? 'Create' : S.save,
          loading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}
