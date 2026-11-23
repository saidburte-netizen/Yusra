import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/state/connectivity.dart';
import '../../../core/state/idempotency.dart';
import '../../../core/state/invalidation.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../../../core/state/async_state_view.dart';
import '../../customers/data/customers.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../sales/data/sales.dart';
import '../../sales/logic/cart.dart';
import '../../sales/logic/held_carts.dart';
import '../../sales/logic/receipts.dart';
import 'payment_dialog.dart';

final posMedicinesProvider =
    FutureProvider.autoDispose<List<Medicine>>((ref) async {
  return ref.read(inventoryRepositoryProvider).medicines(limit: 1000);
});

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  Cart _cart = const Cart();
  String? _customerId;
  String? _prescriptionId;
  HeldCartStore? _heldStore;
  bool _busy = false;
  bool _showCart = false;
  String _saleKey = WriteIdempotency.newKey(Mutation.createSale);

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _heldStore = HeldCartStore(prefs);
        _cart = _heldStore!.loadDraft();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route state is an inherited dependency, so read it here rather than in
    // initState (where GoRouterState.of would register too early).
    try {
      final rxId =
          GoRouterState.of(context).uri.queryParameters['prescription'];
      if (rxId != null) _prescriptionId = rxId;
    } catch (_) {
      // Not under GoRouter (e.g. widget tests).
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _updateCart(Cart cart) {
    setState(() => _cart = cart);
    unawaited(_heldStore?.saveDraft(cart));
  }

  CartLine? _lineFor(Medicine medicine, StockSummary? stock) {
    if (medicine.id.isEmpty) return null;
    return CartLine(
      medicineId: medicine.id,
      name: medicine.name,
      sku: medicine.sku,
      quantity: 1,
      availableQty: stock?.availableQty ?? 0,
      unitPrice: medicine.sellingPrice,
      vatApplicable: medicine.vatApplicable,
      requiresPrescription: medicine.requiresPrescription,
      isControlled: medicine.isControlled,
      nearestExpiry: stock?.nearestExpiry,
    );
  }

  Future<void> _checkout(Shift shift, ReceiptSettings settings) async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    final vatRate = settings.vatRate;
    if (_cart.isEmpty) {
      AppSnackbar.error(context, 'Add at least one medicine to the cart.');
      return;
    }
    if (_cart.hasOverQuantity) {
      AppSnackbar.error(context, 'Check the quantity of every cart item.');
      return;
    }
    if (_cart.needsPrescription && _prescriptionId == null) {
      AppSnackbar.error(context, 'Select a prescription for this sale.');
      return;
    }
    final discountError = validateDiscount(
      discount: _cart.discount,
      subtotal: _cart.subtotal(vatRate),
      role: role,
      maxCashierDiscountPct: settings.maxCashierDiscountPct,
    );
    if (discountError != null) {
      AppSnackbar.error(context, discountError);
      return;
    }

    final payments =
        await showPaymentDialog(context, total: _cart.total(vatRate));
    if (payments == null || !mounted) return;
    final paymentError = validatePayments(
      total: _cart.total(vatRate),
      payments: payments,
    );
    if (paymentError != null) {
      AppSnackbar.error(context, paymentError);
      return;
    }

    setState(() => _busy = true);
    try {
      final saleId = await ref.read(salesRepositoryProvider).createSale(
            branchId: shift.branchId,
            shiftId: shift.id,
            customerId: _customerId,
            prescriptionId: _prescriptionId,
            items: [
              for (final line in _cart.lines)
                {'medicine_id': line.medicineId, 'quantity': line.quantity},
            ],
            payments: payments.map((payment) => payment.toJson()).toList(),
            discount: _cart.discount,
            note: _cart.note,
            idempotencyKey: _saleKey,
          );
      final sale = await ref.read(salesRepositoryProvider).sale(saleId);
      final items = await ref.read(salesRepositoryProvider).saleItems(saleId);
      final savedPayments =
          await ref.read(salesRepositoryProvider).salePayments(saleId);
      await Receipts.printSale(
        sale: sale,
        items: items,
        payments: savedPayments,
        settings: settings,
        cashierName: ref.read(authProvider).profile?.fullName ?? 'Cashier',
      );

      _updateCart(const Cart());
      _discount.clear();
      setState(() {
        _customerId = null;
        _prescriptionId = null;
        _showCart = false;
        _saleKey = WriteIdempotency.newKey(Mutation.createSale);
      });
      await _heldStore?.clearDraft();
      ref.applyMutation(Mutation.createSale);
      if (mounted) {
        AppSnackbar.success(context, 'Sale complete  •  ${sale.invoiceNo}');
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _holdCart() async {
    if (_cart.isEmpty) return;
    final label = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hold cart'),
        content: AppTextField(
          label: 'Label (e.g. customer name)',
          controller: label,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hold'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = _heldStore;
    if (store == null) return;
    try {
      await store.save(HeldCart(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: label.text.trim().isEmpty ? 'Held cart' : label.text.trim(),
        savedAt: DateTime.now(),
        cart: _cart,
      ));
      _updateCart(const Cart());
      await store.clearDraft();
      if (mounted) AppSnackbar.success(context, 'Cart held.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  Future<void> _resumeCart() async {
    final store = _heldStore;
    if (store == null) return;
    final held = store.list();
    if (held.isEmpty) {
      AppSnackbar.show(context, 'No held carts.');
      return;
    }
    final chosen = await showModalBottomSheet<HeldCart>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Held carts', style: TextStyle(fontSize: 18)),
            ),
            ...held.map(
              (item) => ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: Text(item.label),
                subtitle: Text(
                    '${item.cart.itemCount} items  •  ${formatDateTime(item.savedAt)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await store.delete(item.id);
                      if (context.mounted) Navigator.pop(context);
                    } catch (error) {
                      if (context.mounted) {
                        AppSnackbar.error(
                          context,
                          AppErrorMapper.from(error).message,
                        );
                      }
                    }
                  },
                ),
                onTap: () => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await store.delete(chosen.id);
      _updateCart(chosen.cart);
      if (mounted) AppSnackbar.success(context, 'Cart resumed.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  Future<void> _selectCustomer() async {
    final query = TextEditingController();
    final chosen = await showDialog<Customer>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select customer'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: Column(
              children: [
                AppTextField(
                  label: S.search,
                  controller: query,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ref.watch(customersProvider(query.text)).when(
                        data: (customers) => customers.isEmpty
                            ? const EmptyState(
                                message: 'No customers found.',
                                icon: Icons.people_outline)
                            : ListView(
                                children: [
                                  ListTile(
                                    title: const Text('Walk-in customer'),
                                    onTap: () => Navigator.pop(context),
                                  ),
                                  ...customers.map(
                                    (customer) => ListTile(
                                      title: Text(customer.name),
                                      subtitle: Text(customer.phone ?? ''),
                                      selected: customer.id == _customerId,
                                      onTap: () =>
                                          Navigator.pop(context, customer),
                                    ),
                                  ),
                                ],
                              ),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => ErrorState(
                          message: 'Customers could not be loaded.',
                          onRetry: () =>
                              ref.invalidate(customersProvider(query.text)),
                        ),
                      ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(S.cancel),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _customerId = chosen.id);
  }

  /// Opens a shift from inside POS, using the same `open_shift` RPC as the
  /// Shifts screen. No navigation: the banner unlocks the sale immediately.
  Future<void> _openShift() async {
    final branchId = ref.read(branchScopeProvider);
    if (branchId == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    final controller = TextEditingController(text: '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Enter the cash in the drawer when you open your shift.'),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Opening cash (ETB)',
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start shift'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(controller.text.replaceAll(',', '')) ?? 0;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).openShift(branchId, amount);
      ref.invalidate(myOpenShiftProvider);
      ref.invalidate(shiftsProvider(true));
      if (mounted) AppSnackbar.success(context, 'Shift started.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeShift(Shift shift) async {
    final countedController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Opened ${formatDateTime(shift.openedAt ?? DateTime.now())}'),
            const SizedBox(height: 8),
            Text('Opening cash ${formatMoney(shift.openingCash)}'),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Counted cash (ETB)',
              controller: countedController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            AppTextField(label: 'Note (optional)', controller: noteController),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close shift'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final counted = double.tryParse(countedController.text.replaceAll(',', ''));
    if (counted == null) {
      AppSnackbar.error(context, 'Enter the counted cash.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).closeShift(
            shift.id,
            counted,
            noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
          );
      ref.invalidate(myOpenShiftProvider);
      ref.invalidate(shiftsProvider(true));
      if (mounted) AppSnackbar.success(context, 'Shift closed.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftState = ref.watch(myOpenShiftProvider);
    final settingsState = ref.watch(receiptSettingsProvider);
    final medicinesState = ref.watch(posMedicinesProvider);
    final stockState = ref.watch(stockSummaryProvider);
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canSell = can(role, Modules.pos, PermAction.edit);
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    if (!canSell) {
      return const Scaffold(
        body: EmptyState(
          message: 'Your role cannot use the point of sale.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final settings = settingsState.valueOrNull ??
        const ReceiptSettings(
          pharmacyName: 'Yusra Pharmacy',
          tagline: 'Care made easy',
          address: '',
          phone: '',
          tin: '',
          licenseNo: '',
          footer: 'Thank you for choosing Yusra Pharmacy.',
          vatRate: 0.15,
          maxCashierDiscountPct: 5,
        );
    final shift = shiftState.valueOrNull;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'New sale',
              subtitle: shift == null
                  ? 'Open a cash shift before selling'
                  : 'Shift open  •  ${formatDateTime(shift.openedAt ?? DateTime.now())}',
              actions: [
                if (wide) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SecondaryButton(
                      label: 'Held (${_heldStore?.list().length ?? 0})',
                      icon: Icons.bookmark_border,
                      width: 110,
                      onPressed: _resumeCart,
                    ),
                  ),
                  if (shift != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SecondaryButton(
                        label: 'Close shift',
                        icon: Icons.lock_outline,
                        width: 110,
                        onPressed: () => _closeShift(shift),
                      ),
                    ),
                  IconButton(
                    tooltip: S.refresh,
                    onPressed: () {
                      ref.invalidate(posMedicinesProvider);
                      ref.invalidate(stockSummaryProvider);
                    },
                    icon: const Icon(Icons.refresh),
                  ),
                ] else
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'held') _resumeCart();
                      if (value == 'close' && shift != null) _closeShift(shift);
                      if (value == 'refresh') {
                        ref.invalidate(posMedicinesProvider);
                        ref.invalidate(stockSummaryProvider);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'held',
                        child: Text('Held (${_heldStore?.list().length ?? 0})'),
                      ),
                      if (shift != null)
                        const PopupMenuItem(
                          value: 'close',
                          child: Text('Close shift'),
                        ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Text('Refresh'),
                      ),
                    ],
                  ),
              ],
            ),
            if (settingsState.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InlineErrorBanner(
                  error: settingsState.error!,
                  onRetry: () => ref.invalidate(receiptSettingsProvider),
                ),
              ),
            if (shift == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FilledButton.icon(
                    onPressed: _openShift,
                    icon: const Icon(Icons.play_arrow, size: 28),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      textStyle: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    label: const Text('Open shift'),
                  ),
                ),
              ),
            if (_cart.needsPrescription)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Card(
                  color: _prescriptionId == null
                      ? AppColors.danger.withOpacity(0.08)
                      : null,
                  child: ListTile(
                    leading: const Icon(Icons.medical_information),
                    title: Text(_prescriptionId == null
                        ? 'Prescription required'
                        : 'Prescription selected'),
                    subtitle: const Text('Rx-only medicines are in this cart.'),
                    trailing: _prescriptionId == null
                        ? TextButton(
                            onPressed: () => context.go('/prescriptions'),
                            child: const Text('Choose'),
                          )
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _prescriptionId = null),
                          ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _productPane(medicinesState, stockState),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 380,
                          child: _cartPane(settings, shift, canSell),
                        ),
                      ],
                    )
                  : _productPane(medicinesState, stockState),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !wide
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: (_cart.isEmpty || shift == null)
                      ? null
                      : () async {
                          setState(() => _showCart = true);
                          await _checkout(shift, settings);
                        },
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Cart (${_cart.itemCount}) · ${formatMoney(_cart.total(settings.vatRate))} · Pay',
                    ),
                  ),
                ),
              ),
            )
          : null,
      bottomSheet: !wide && _showCart && MediaQuery.sizeOf(context).height > 480
          ? SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: _cartPane(settings, shift, canSell),
            )
          : null,
    );
  }

  Widget _productPane(
    AsyncValue<List<Medicine>> medicinesState,
    AsyncValue<List<StockSummary>> stockState,
  ) {
    final query = _search.text.trim().toLowerCase();
    final medicines = medicinesState.valueOrNull ?? const <Medicine>[];
    final stock = {
      for (final row in stockState.valueOrNull ?? const <StockSummary>[])
        row.medicineId: row,
    };
    final visible = medicines.where((medicine) {
      if (!medicine.isActive) return false;
      if (query.isEmpty) return true;
      return medicine.name.toLowerCase().contains(query) ||
          medicine.sku.toLowerCase().contains(query) ||
          (medicine.genericName ?? '').toLowerCase().contains(query) ||
          (medicine.barcode ?? '').contains(_search.text.trim());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                label: 'Find medicine by name, SKU or barcode',
                controller: _search,
                prefixIcon: const Icon(Icons.search, size: 20),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            BarcodeScanButton(
              compact: true,
              onDetected: (code) {
                setState(() => _search.text = code);
                final match = medicines
                    .where(
                      (medicine) =>
                          medicine.barcode == code || medicine.sku == code,
                    )
                    .firstOrNull;
                if (match != null) {
                  final line = _lineFor(match, stock[match.id]);
                  if (line != null) _updateCart(_cart.add(line));
                  _search.clear();
                } else {
                  AppSnackbar.error(context, 'No medicine found for $code');
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: medicinesState.isLoading || stockState.isLoading
              ? const LoadingSkeleton(lines: 5)
              : medicinesState.hasError || stockState.hasError
                  ? ErrorState(
                      message: AppErrorMapper.from(
                              (medicinesState.error ?? stockState.error)!)
                          .message,
                      onRetry: () {
                        ref.invalidate(posMedicinesProvider);
                        ref.invalidate(stockSummaryProvider);
                      },
                    )
                  : visible.isEmpty
                      ? const EmptyState(
                          message: 'No medicines found.',
                          icon: Icons.medication_outlined,
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 148,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final medicine = visible[index];
                            final available =
                                stock[medicine.id]?.availableQty ?? 0;
                            return Card(
                              child: InkWell(
                                onTap: () {
                                  if (available < 1) {
                                    AppSnackbar.error(
                                      context,
                                      'No stock. Add stock in Inventory.',
                                    );
                                    return;
                                  }
                                  final line =
                                      _lineFor(medicine, stock[medicine.id]);
                                  if (line != null) {
                                    _updateCart(_cart.add(line));
                                  }
                                },
                                borderRadius:
                                    BorderRadius.circular(AppColors.radius),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (medicine.requiresPrescription)
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(right: 4),
                                              child: Icon(
                                                  Icons.medical_information,
                                                  size: 14,
                                                  color: AppColors.gold700),
                                            ),
                                          Expanded(
                                            child: Text(
                                              medicine.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(medicine.sku,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall),
                                      const Spacer(),
                                      Text(formatMoney(medicine.sellingPrice),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.pink600,
                                          )),
                                      Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          available < 1
                                              ? Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.danger
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                  ),
                                                  child: const Text(
                                                    'Out of stock',
                                                    style: TextStyle(
                                                      color: AppColors.danger,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  '$available ${medicine.unit} available',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                          color:
                                                              AppColors.muted),
                                                ),
                                          const Icon(Icons.add_circle_outline,
                                              color: AppColors.gold700),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _cartPane(
    ReceiptSettings settings,
    Shift? shift,
    bool canSell,
  ) {
    final total = _cart.total(settings.vatRate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Cart  •  ${_cart.itemCount} items',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_cart.lines.isNotEmpty)
                  TextButton(
                    onPressed: () => _updateCart(_cart.clear()),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_customerId == null
                  ? 'Walk-in customer'
                  : 'Customer selected'),
              trailing: TextButton(
                onPressed: _selectCustomer,
                child: const Text('Change'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _cart.lines.isEmpty
                  ? const EmptyState(
                      message: 'Add medicines to start a sale.',
                      icon: Icons.shopping_cart_outlined,
                    )
                  : ListView(
                      children: [
                        for (final line in _cart.lines)
                          Card(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.darkElevated
                                    : AppColors.pink50,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(line.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                        Text(
                                          '${formatMoney(line.unitPrice)}'
                                          '${line.vatApplicable ? ' + VAT' : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20),
                                    onPressed: () =>
                                        _updateCart(_cart.setQuantity(
                                      line.medicineId,
                                      line.quantity - 1,
                                    )),
                                  ),
                                  Text('${line.quantity}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    onPressed: line.quantity >=
                                            line.availableQty
                                        ? null
                                        : () => _updateCart(_cart.setQuantity(
                                              line.medicineId,
                                              line.quantity + 1,
                                            )),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppColors.danger),
                                    onPressed: () => _updateCart(
                                        _cart.remove(line.medicineId)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal'),
                Text(formatMoney(_cart.subtotal(settings.vatRate))),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('VAT (${(settings.vatRate * 100).toStringAsFixed(0)}%)'),
                Text(formatMoney(_cart.tax(settings.vatRate))),
              ],
            ),
            Row(
              children: [
                const Text('Discount'),
                const Spacer(),
                SizedBox(
                  width: 100,
                  child: AppTextField(
                    label: '',
                    controller: _discount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) => _updateCart(_cart.withDiscount(
                      double.tryParse(value.replaceAll(',', '')) ?? 0,
                      settings.vatRate,
                    )),
                  ),
                ),
              ],
            ),
            if (roleIsCashier(ref) && _cart.discount > 0)
              Text(
                'Cashier limit ${settings.maxCashierDiscountPct.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  formatMoney(total),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.pink600,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Hold',
                    icon: Icons.bookmark_border,
                    onPressed: _cart.isEmpty ? null : _holdCart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    label: _busy ? 'Saving…' : 'Pay ${formatMoney(total)}',
                    icon: Icons.payment,
                    loading: _busy,
                    onPressed: shift == null ||
                            _cart.isEmpty ||
                            !canSell ||
                            _busy ||
                            !writeEnabled(ref)
                        ? null
                        : () => _checkout(shift, settings),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool roleIsCashier(WidgetRef ref) =>
    ref.read(authProvider).profile?.role == AppRole.cashier;
