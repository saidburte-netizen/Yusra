import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/widgets/stock_widgets.dart';
import '../../suppliers/data/suppliers.dart';
import '../data/purchase_documents.dart';
import '../data/purchasing.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/strings.dart';
import '../../inventory/widgets/responsive_ui.dart';

/// B11/B12 — create/edit a draft, approve, print, and receive goods.
///
/// Purchase orders have no physical delete action by design: the database keeps
/// immutable order history, so removal is a status transition to `cancelled`
/// through the status RPC. This screen exposes that transition as "Cancel"
/// instead of a fake delete button.
class PurchaseOrderScreen extends ConsumerStatefulWidget {
  const PurchaseOrderScreen({super.key, required this.orderId});

  /// 'new' creates a draft; any other value opens that order.
  final String orderId;

  @override
  ConsumerState<PurchaseOrderScreen> createState() =>
      _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  bool get _isNew => widget.orderId == 'new';

  final _supplier = GlobalKey<FormState>();
  String? _supplierId;
  DateTime? _expectedDate;
  final _notes = TextEditingController();
  final _tax = TextEditingController(text: '0');
  List<PurchaseOrderItem> _lines = [];
  PurchaseOrder? _order;
  bool _loading = true;
  bool _saving = false;

  final Map<String, TextEditingController> _receiveQty = {};
  final Map<String, TextEditingController> _receiveBatch = {};
  final Map<String, DateTime?> _receiveExpiry = {};

  @override
  void initState() {
    super.initState();
    _tax.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    _tax.dispose();
    for (final controller in _receiveQty.values) {
      controller.dispose();
    }
    for (final controller in _receiveBatch.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_isNew) {
        final repo = ref.read(purchaseRepositoryProvider);
        final order = await repo.order(widget.orderId);
        final items = await repo.items(widget.orderId);
        setState(() {
          _order = order;
          _supplierId = order.supplierId;
          _expectedDate = order.expectedDate;
          _notes.text = order.notes ?? '';
          _tax.text = '${order.tax}';
          _lines = items;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _order = null;
      });
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  double get _subtotal => _lines.fold(0, (sum, line) => sum + line.lineTotal);
  double get _taxValue => parseMoney(_tax.text) ?? 0;
  double get _total => _subtotal + _taxValue;

  bool get _canEditDraft {
    if (!_isNew && _order?.status != 'draft') return false;
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    return can(role, Modules.purchaseOrders, PermAction.edit);
  }

  /// Approving, cancelling and receiving are edits to a purchase order, so
  /// they follow the permission matrix rather than an admin-role check.
  bool get _canManage {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    return can(role, Modules.purchaseOrders, PermAction.edit);
  }

  Future<void> _saveDraft() async {
    if (!_supplier.currentState!.validate()) return;
    if (_lines.isEmpty) {
      AppSnackbar.error(context, 'Add at least one line.');
      return;
    }
    final branch = ref.read(branchScopeProvider);
    if (branch == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(purchaseRepositoryProvider);
      if (_isNew) {
        final id = await repo.createDraft(
          branchId: branch,
          supplierId: _supplierId!,
          expectedDate: _expectedDate,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          tax: _taxValue,
          lines: _lines,
        );
        ref.invalidate(purchaseOrdersProvider);
        if (!mounted) return;
        AppSnackbar.success(context, 'Draft created.');
        context.go('/purchasing/orders/$id');
      } else {
        await repo.updateDraft(
          id: widget.orderId,
          supplierId: _supplierId!,
          expectedDate: _expectedDate,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          tax: _taxValue,
        );
        await repo.saveLines(widget.orderId, _lines);
        ref.invalidate(purchaseOrderProvider(widget.orderId));
        ref.invalidate(purchaseItemsProvider(widget.orderId));
        ref.invalidate(purchaseOrdersProvider);
        if (!mounted) return;
        AppSnackbar.success(context, 'Draft saved.');
        await _load();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(String status) async {
    if (!_canManage) {
      AppSnackbar.error(context, 'You cannot change this order.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(purchaseRepositoryProvider)
          .setStatus(widget.orderId, status);
      ref.invalidate(purchaseOrderProvider(widget.orderId));
      ref.invalidate(purchaseOrdersProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Order $status.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addLine() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _LinePickerDialog(),
    );
    if (picked == null) return;
    final medicine = picked['medicine'] as Medicine;
    setState(() {
      _lines = [
        ..._lines,
        PurchaseOrderItem(
          id: '',
          poId: widget.orderId,
          medicineId: medicine.id,
          quantityOrdered: (picked['qty'] as int?) ?? 1,
          unitCost: (picked['cost'] as double?) ?? medicine.costPrice,
          medicineName: medicine.name,
        ),
      ];
    });
  }

  void _editLine(int index) async {
    final line = _lines[index];
    final qty = TextEditingController(text: '${line.quantityOrdered}');
    final cost = TextEditingController(text: '${line.unitCost}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(line.medicineName),
        content: SizedBox(
          width: dialogContentWidth(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Quantity',
                controller: qty,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              MoneyField(label: 'Unit cost', controller: cost),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ResponsivePrimaryButton(
            label: 'Save',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (saved != true) return;
    setState(() {
      _lines[index] = PurchaseOrderItem(
        id: line.id,
        poId: line.poId,
        medicineId: line.medicineId,
        quantityOrdered: int.tryParse(qty.text) ?? 1,
        unitCost: parseMoney(cost.text) ?? 0,
        medicineName: line.medicineName,
        quantityReceived: line.quantityReceived,
      );
    });
  }

  Future<void> _printOrder() async {
    final supplier =
        (ref.read(suppliersProvider('')).value ?? const <Supplier>[])
            .where((item) => item.id == _supplierId)
            .firstOrNull;
    try {
      await PurchaseDocuments.printOrder(
        order: _order ??
            PurchaseOrder(
              id: '',
              poNo: '(draft)',
              branchId: '',
              supplierId: _supplierId ?? '',
              orderDate: DateTime.now(),
              subtotal: _subtotal,
              tax: _taxValue,
              total: _total,
              notes: _notes.text,
            ),
        supplier: supplier,
        items: _lines,
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _printGrn() async {
    final supplier =
        (ref.read(suppliersProvider('')).value ?? const <Supplier>[])
            .where((item) => item.id == _supplierId)
            .firstOrNull;
    final order = _order;
    if (order == null) return;
    try {
      await PurchaseDocuments.printOrder(
        order: order,
        supplier: supplier,
        items: _lines,
        goodsReceivedNote: true,
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _receive() async {
    if (!_canManage) {
      AppSnackbar.error(context, 'You cannot receive goods on this order.');
      return;
    }
    final payload = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final remaining = line.remaining;
      if (remaining <= 0) continue;
      final qty = int.tryParse(_receiveQty[line.id]?.text ?? '') ?? 0;
      if (qty == 0) continue;
      final batch = _receiveBatch[line.id]?.text.trim() ?? '';
      final expiry = _receiveExpiry[line.id];
      if (batch.isEmpty) {
        AppSnackbar.error(
            context, 'Batch number is required for ${line.medicineName}.');
        return;
      }
      if (expiry == null || !expiry.isAfter(DateTime.now())) {
        AppSnackbar.error(context,
            'Future expiry date is required for ${line.medicineName}.');
        return;
      }
      if (qty > remaining) {
        AppSnackbar.error(context,
            'Received quantity exceeds the amount due for ${line.medicineName}.');
        return;
      }
      payload.add({
        'po_item_id': line.id,
        'quantity': qty,
        'batch_no': batch,
        'expiry_date': formatIsoDate(expiry),
      });
    }
    if (payload.isEmpty) {
      AppSnackbar.error(context, 'Enter a quantity to receive.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(purchaseRepositoryProvider)
          .receive(widget.orderId, payload);
      ref.invalidate(purchaseOrderProvider(widget.orderId));
      ref.invalidate(purchaseItemsProvider(widget.orderId));
      ref.invalidate(purchaseOrdersProvider);
      ref.invalidate(batchesProvider(null));
      ref.invalidate(stockSummaryProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Goods received and stock updated.');
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider(''));
    final status = _order?.status ?? 'draft';
    final openForReceiving =
        status == 'ordered' || status == 'partially_received';

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _supplier,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: _isNew
                          ? 'New purchase order'
                          : 'Purchase order ${_order?.poNo ?? ''}',
                      subtitle: 'Status: ${status.replaceAll('_', ' ')}',
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ResponsiveSecondaryButton(
                            label: 'Print PO',
                            icon: Icons.picture_as_pdf_outlined,
                            onPressed: _printOrder,
                          ),
                        ),
                        if (!_isNew &&
                            status != 'draft' &&
                            status != 'cancelled')
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ResponsiveSecondaryButton(
                              label: 'Print GRN',
                              icon: Icons.print_outlined,
                              onPressed: _printGrn,
                            ),
                          ),
                        if (!_isNew && _canManage && status == 'draft') ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ResponsiveSecondaryButton(
                              label: 'Cancel',
                              onPressed: _saving
                                  ? null
                                  : () => _setStatus('cancelled'),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ResponsivePrimaryButton(
                              label: 'Approve & send',
                              icon: Icons.send_outlined,
                              loading: _saving,
                              onPressed: () => _setStatus('ordered'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 600;
                                    final wide =
                                        compact ? constraints.maxWidth : 280.0;
                                    return Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        SizedBox(
                                          width: wide,
                                          child: suppliers.when(
                                            data: (items) =>
                                                AppDropdown<String>(
                                              label: 'Supplier',
                                              value: _supplierId,
                                              items: [
                                                for (final supplier in items)
                                                  DropdownMenuItem(
                                                    value: supplier.id,
                                                    child: Text(supplier.name),
                                                  ),
                                              ],
                                              onChanged: _canEditDraft
                                                  ? (value) => setState(
                                                      () => _supplierId = value)
                                                  : null,
                                              validator: (value) =>
                                                  value == null
                                                      ? 'Required'
                                                      : null,
                                            ),
                                            loading: () =>
                                                const SizedBox(height: 56),
                                            error: (_, __) =>
                                                const SizedBox(height: 56),
                                          ),
                                        ),
                                        SizedBox(
                                          width: wide,
                                          child: DatePickerField(
                                            label: 'Expected date',
                                            value: _expectedDate,
                                            onChanged: (value) {
                                              if (_canEditDraft) {
                                                setState(() =>
                                                    _expectedDate = value);
                                              }
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: compact
                                              ? (constraints.maxWidth - 12) / 2
                                              : 140,
                                          child: MoneyField(
                                            label: 'Tax',
                                            controller: _tax,
                                          ),
                                        ),
                                        SizedBox(
                                          width: wide,
                                          child: AppTextField(
                                            label: 'Notes',
                                            controller: _notes,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Text('Lines',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const Spacer(),
                                if (_canEditDraft)
                                  ResponsiveSecondaryButton(
                                    label: 'Add line',
                                    icon: Icons.add,
                                    onPressed: _addLine,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Card(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Medicine')),
                                    DataColumn(label: Text('Ordered')),
                                    DataColumn(label: Text('Received')),
                                    DataColumn(label: Text('Unit cost')),
                                    DataColumn(label: Text('Total')),
                                    DataColumn(label: Text('')),
                                  ],
                                  rows: [
                                    for (var i = 0; i < _lines.length; i++)
                                      DataRow(cells: [
                                        DataCell(Text(_lines[i].medicineName)),
                                        DataCell(Text(
                                            '${_lines[i].quantityOrdered}')),
                                        DataCell(Text(
                                            '${_lines[i].quantityReceived}')),
                                        DataCell(Text(
                                            formatMoney(_lines[i].unitCost))),
                                        DataCell(Text(
                                            formatMoney(_lines[i].lineTotal))),
                                        DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_canEditDraft)
                                              IconButton(
                                                tooltip: 'Edit line',
                                                icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18),
                                                onPressed: () => _editLine(i),
                                              ),
                                            if (_canEditDraft)
                                              IconButton(
                                                tooltip: 'Remove line',
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18),
                                                onPressed: () => setState(
                                                    () => _lines.removeAt(i)),
                                              ),
                                          ],
                                        )),
                                      ]),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Subtotal: ${formatMoney(_subtotal)}'),
                                  Text('Tax: ${formatMoney(_taxValue)}'),
                                  Text('Total: ${formatMoney(_total)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            if (_canEditDraft) ...[
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ResponsivePrimaryButton(
                                  label: _isNew ? 'Create draft' : 'Save draft',
                                  icon: Icons.save_outlined,
                                  loading: _saving,
                                  onPressed: _saveDraft,
                                ),
                              ),
                            ],
                            if (openForReceiving && _canManage) ...[
                              const SizedBox(height: 22),
                              Text('Goods receiving',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      for (final line in _lines)
                                        if (line.remaining > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: _ReceiveLine(
                                              line: line,
                                              qtyController:
                                                  _receiveQty.putIfAbsent(
                                                line.id,
                                                () => TextEditingController(),
                                              ),
                                              batchController:
                                                  _receiveBatch.putIfAbsent(
                                                line.id,
                                                () => TextEditingController(),
                                              ),
                                              expiry: _receiveExpiry[line.id],
                                              onExpiry: (value) => setState(
                                                  () =>
                                                      _receiveExpiry[line.id] =
                                                          value),
                                            ),
                                          ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: ResponsivePrimaryButton(
                                          label: 'Receive goods',
                                          icon: Icons.inventory_outlined,
                                          loading: _saving,
                                          onPressed: _receive,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ReceiveLine extends StatelessWidget {
  const _ReceiveLine({
    required this.line,
    required this.qtyController,
    required this.batchController,
    required this.expiry,
    required this.onExpiry,
  });

  final PurchaseOrderItem line;
  final TextEditingController qtyController;
  final TextEditingController batchController;
  final DateTime? expiry;
  final ValueChanged<DateTime> onExpiry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final qtyWidth = stacked ? (constraints.maxWidth - 8) / 2 : 90.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: stacked ? constraints.maxWidth : 180,
              child: Text('${line.medicineName}\nDue: ${line.remaining}'),
            ),
            SizedBox(
              width: qtyWidth,
              child: AppTextField(
                label: 'Qty now',
                controller: qtyController,
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(
              width: stacked ? qtyWidth : 160,
              child: AppTextField(
                label: 'Batch no',
                controller: batchController,
              ),
            ),
            SizedBox(
              width: stacked ? constraints.maxWidth : 160,
              child: DatePickerField(
                label: 'Expiry',
                value: expiry,
                firstDate: DateTime.now().add(const Duration(days: 1)),
                onChanged: onExpiry,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LinePickerDialog extends ConsumerStatefulWidget {
  const _LinePickerDialog();

  @override
  ConsumerState<_LinePickerDialog> createState() => _LinePickerDialogState();
}

class _LinePickerDialogState extends ConsumerState<_LinePickerDialog> {
  final _search = TextEditingController();
  Medicine? _selected;
  final _qty = TextEditingController(text: '1');
  final _cost = TextEditingController(text: '0');

  @override
  void dispose() {
    _search.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final medicines = ref.watch(medicinesProvider(
      (query: _search.text, categoryId: null),
    ));
    return AlertDialog(
      title: const Text('Add medicine'),
      content: SizedBox(
        width: dialogContentWidth(context),
        height: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Search name or scan barcode',
              controller: _search,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: BarcodeScanButton(
                compact: true,
                onDetected: (code) => setState(() => _search.text = code),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: medicines.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    ErrorState(message: AppErrorMapper.from(error).message),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      selected: _selected?.id == item.id,
                      title: Text(item.name),
                      subtitle: Text(
                          '${item.sku}  •  ${formatMoney(item.costPrice)}'),
                      onTap: () => setState(() {
                        _selected = item;
                        _cost.text = '${item.costPrice}';
                      }),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: AppTextField(
                    label: 'Quantity',
                    controller: _qty,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: MoneyField(label: 'Unit cost', controller: _cost)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ResponsivePrimaryButton(
          label: 'Add',
          onPressed: () {
            if (_selected == null) return;
            Navigator.pop(context, {
              'medicine': _selected,
              'qty': int.tryParse(_qty.text) ?? 1,
              'cost': parseMoney(_cost.text) ?? 0.0,
            });
          },
        ),
      ],
    );
  }
}
