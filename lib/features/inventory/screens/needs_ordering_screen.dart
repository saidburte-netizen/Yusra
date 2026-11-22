import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/state/connectivity.dart';
import '../../../core/state/idempotency.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../data/inventory_providers.dart';
import '../data/reorder_models.dart';
import '../widgets/responsive_ui.dart';
import '../widgets/stock_widgets.dart';

/// Editable reorder workspace backed by `v_reorder_suggestions`. Selected rows
/// are turned into one draft purchase order per supplier in a single RPC call.
class NeedsOrderingScreen extends ConsumerStatefulWidget {
  const NeedsOrderingScreen({super.key});

  @override
  ConsumerState<NeedsOrderingScreen> createState() =>
      _NeedsOrderingScreenState();
}

/// Per-medicine edits live in a map keyed by medicine id so typing a quantity,
/// toggling selection or choosing a supplier survives provider rebuilds.
class _EditableReorderRow {
  _EditableReorderRow({required String suggestedQty, this.supplierId})
      : quantity = TextEditingController(text: suggestedQty);

  final TextEditingController quantity;
  bool selected = true;
  String? supplierId;

  int get orderQty => int.tryParse(quantity.text.trim()) ?? 0;

  void dispose() => quantity.dispose();
}

class _NeedsOrderingScreenState extends ConsumerState<NeedsOrderingScreen> {
  final Map<String, _EditableReorderRow> _edits =
      <String, _EditableReorderRow>{};
  List<SupplierOption> _suppliers = const <SupplierOption>[];
  bool _busy = false;
  String _draftKey =
      WriteIdempotency.newKey(Mutation.createDraftPurchaseOrders);

  static const List<String> _columns = <String>[
    'medicine',
    'sku',
    'on_hand',
    'available_qty',
    'expiring_qty',
    'reorder_level',
    'target_level',
    'order_qty',
    'supplier',
    'last_cost',
    'reason',
  ];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (final row in _edits.values) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final options = await SupplierOption.load(ref);
    if (!mounted) return;
    setState(() => _suppliers = options);
  }

  void _refresh() {
    ref.invalidate(reorderSuggestionsProvider);
    _loadSuppliers();
  }

  void _syncEdits(List<ReorderSuggestion> rows) {
    final ids = <String>{for (final row in rows) row.medicineId};
    for (final id in _edits.keys.toList()) {
      if (!ids.contains(id)) _edits.remove(id)!.dispose();
    }
    for (final row in rows) {
      if (_edits.containsKey(row.medicineId)) continue;
      final preferred = row.preferredSupplierId;
      _edits[row.medicineId] = _EditableReorderRow(
        suggestedQty: '${row.suggestedOrderQty}',
        supplierId:
            preferred == null || preferred.trim().isEmpty ? null : preferred,
      );
    }
  }

  List<ReorderSuggestion> _selected(List<ReorderSuggestion> rows) =>
      rows.where((row) => _edits[row.medicineId]?.selected ?? true).toList();

  bool _needsSupplier(ReorderSuggestion row) {
    final supplierId = _edits[row.medicineId]?.supplierId;
    return _edits[row.medicineId]?.selected == true &&
        (supplierId == null || supplierId.trim().isEmpty);
  }

  String _supplierName(ReorderSuggestion row) {
    final id = _edits[row.medicineId]?.supplierId ?? row.preferredSupplierId;
    if (id == null || id.isEmpty) return '';
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier.name;
    }
    return row.preferredSupplierName ?? id;
  }

  /// Keeps the preferred supplier visible even when the supplier table could
  /// not be loaded (or the preferred supplier was deactivated).
  List<DropdownMenuItem<String?>> _supplierItems(ReorderSuggestion row) {
    final current = _edits[row.medicineId]?.supplierId;
    final options = <SupplierOption>[..._suppliers];
    if (current != null &&
        current.isNotEmpty &&
        !options.any((option) => option.id == current)) {
      options.add(
        SupplierOption(
          id: current,
          name: current == row.preferredSupplierId
              ? (row.preferredSupplierName ?? current)
              : current,
        ),
      );
    }
    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Choose supplier'),
      ),
      for (final option in options)
        DropdownMenuItem<String?>(
          value: option.id,
          child: Text(option.name, overflow: TextOverflow.ellipsis),
        ),
    ];
  }

  Widget _supplierField(ReorderSuggestion row, {required String label}) =>
      AppDropdown<String?>(
        label: label,
        value: _edits[row.medicineId]?.supplierId,
        items: _supplierItems(row),
        onChanged: (value) => setState(() {
          _edits[row.medicineId]!.supplierId =
              value == null || value.trim().isEmpty ? null : value;
        }),
      );

  Future<void> _createOrders(List<ReorderSuggestion> rows) async {
    final selected = _selected(rows);
    if (selected.isEmpty) {
      AppSnackbar.error(context, 'Select at least one row.');
      return;
    }
    if (selected.any(_needsSupplier)) {
      AppSnackbar.error(
        context,
        'Assign a supplier for every selected row in "Choose supplier" '
        'before creating orders.',
      );
      return;
    }
    final quantities = <String, int>{};
    for (final row in selected) {
      final quantity = _edits[row.medicineId]!.orderQty;
      if (quantity <= 0) {
        AppSnackbar.error(
          context,
          'Order quantity for ${row.name} must be a whole number above zero.',
        );
        return;
      }
      quantities[row.medicineId] = quantity;
    }
    final branch = ref.read(branchScopeProvider);
    if (branch == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }

    setState(() => _busy = true);
    try {
      final ids =
          await ref.read(inventoryRepositoryProvider).createDraftPurchaseOrders(
                branchId: branch,
                lines: [
                  for (final row in selected)
                    {
                      'supplier_id': _edits[row.medicineId]!.supplierId,
                      'medicine_id': row.medicineId,
                      'quantity': quantities[row.medicineId],
                      'unit_cost': row.lastPurchaseCost,
                    },
                ],
                idempotencyKey: _draftKey,
              );
      if (!mounted) return;
      AppSnackbar.success(
        context,
        ids.isEmpty
            ? 'Created draft purchase orders for ${selected.length} line(s).'
            : 'Created ${ids.length} purchase order(s): ${ids.join(', ')}',
      );
      setState(() => _draftKey =
          WriteIdempotency.newKey(Mutation.createDraftPurchaseOrders));
      ref.applyMutation(Mutation.createDraftPurchaseOrders);
      if (GoRouter.maybeOf(context) != null) {
        context.go('/purchasing/orders');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<dynamic> _exportRow(ReorderSuggestion row) => <dynamic>[
        row.name,
        row.sku ?? '',
        '${row.onHand}',
        '${row.availableQty}',
        '${row.expiringQty}',
        '${row.reorderLevel}',
        '${row.targetLevel}',
        '${_edits[row.medicineId]?.orderQty ?? row.suggestedOrderQty}',
        _supplierName(row),
        row.lastPurchaseCost.toStringAsFixed(2),
        row.reason,
      ];

  List<ReorderSuggestion> _exportRows(List<ReorderSuggestion> rows) {
    final selected = _selected(rows);
    return selected.isNotEmpty ? selected : rows;
  }

  Future<void> _exportCsv(List<ReorderSuggestion> rows) async {
    try {
      final exportRows = _exportRows(rows);
      final csv = CsvCodec(eol: '\n').encoder.convert(<List<dynamic>>[
        _columns,
        for (final row in exportRows) _exportRow(row),
      ]);
      // Byte-based XFile works on web as well as mobile: no dart:io File.
      final file = XFile.fromData(
        utf8.encode(csv),
        mimeType: 'text/csv',
        name: 'yusra-needs-ordering.csv',
      );
      try {
        await Share.shareXFiles(
          [file],
          subject: 'yusra-needs-ordering.csv',
        );
      } catch (_) {
        await Share.share(csv);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    }
  }

  Future<void> _exportPdf(List<ReorderSuggestion> rows) async {
    try {
      final exportRows = _exportRows(rows);
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => <pw.Widget>[
            pw.Header(level: 0, child: pw.Text('Needs ordering')),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: _columns,
              data: [for (final row in exportRows) _exportRow(row)],
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.pink50),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: const pw.TextStyle(fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Thank you for choosing Yusra Pharmacy.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      );
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'yusra-needs-ordering.pdf',
      );
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    }
  }

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.blush,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.muted, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Widget _chooseSupplierCard(List<ReorderSuggestion> rows) => Card(
        color: const Color(0xFFFFF8E1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          side: const BorderSide(color: AppColors.warning, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Choose supplier',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Assign a supplier to every selected row below before '
                'creating purchase orders.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final row in rows) ...[
                Text(
                  row.sku == null || row.sku!.trim().isEmpty
                      ? row.name
                      : '${row.name} (${row.sku})',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                _supplierField(row, label: 'Supplier'),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );

  Widget _rowCard(ReorderSuggestion row) {
    final edit = _edits[row.medicineId]!;
    final needsSupplier = _needsSupplier(row);
    final label = row.sku == null || row.sku!.trim().isEmpty
        ? row.name
        : '${row.name} (${row.sku})';
    return Card(
      shape: needsSupplier
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radius),
              side: const BorderSide(color: AppColors.warning, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Checkbox(
                    value: edit.selected,
                    onChanged: (value) =>
                        setState(() => edit.selected = value ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (needsSupplier)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 20, color: AppColors.warning),
                  ),
              ],
            ),
            if (needsSupplier) ...[
              const SizedBox(height: 4),
              Text(
                'Supplier needed — assign it in "Choose supplier" above.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.warning),
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final max =
                    constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
                final width = max >= 480 ? (max - 36) / 4 : (max - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _metric('On hand', '${row.onHand} ${row.unit}'),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric('Available', '${row.availableQty}'),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric('Expiring qty', '${row.expiringQty}'),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric('Reorder level', '${row.reorderLevel}'),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric('Target level', '${row.targetLevel}'),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric('Last purchase cost',
                          formatMoney(row.lastPurchaseCost)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Reason: ${row.reason.isEmpty ? '—' : row.reason}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final max =
                    constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
                final width = max >= 600 ? (max - 12) / 2 : max;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: AppTextField(
                        label: 'Order quantity',
                        controller: edit.quantity,
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            (int.tryParse(value?.trim() ?? '') ?? 0) > 0
                                ? null
                                : 'Must be above zero',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _supplierField(row, label: 'Preferred supplier'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.stock, PermAction.edit)) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have access to ordering suggestions.'),
        ),
      );
    }

    final branch = ref.watch(branchScopeProvider);
    final state = ref.watch(reorderSuggestionsProvider(branch));
    final rows = state.value ?? const <ReorderSuggestion>[];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Needs ordering',
                subtitle: 'Stock at or below reorder level, zero stock, or '
                    'expiring within 30 days.',
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsivePrimaryButton(
                      label: 'Create purchase order(s)',
                      icon: Icons.shopping_cart_outlined,
                      loading: _busy,
                      onPressed: !state.hasValue || _busy || !writeEnabled(ref)
                          ? null
                          : () => _createOrders(rows),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsiveSecondaryButton(
                      label: 'Export / share CSV',
                      icon: Icons.file_download_outlined,
                      onPressed: state.hasValue ? () => _exportCsv(rows) : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsiveSecondaryButton(
                      label: 'Export / share PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: state.hasValue ? () => _exportPdf(rows) : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Expanded(
                child: stockState(
                  state,
                  onRetry: _refresh,
                  builder: (suggestions) {
                    if (suggestions.isEmpty) {
                      return const EmptyState(
                        message: 'Nothing needs ordering right now. Stock is '
                            'above reorder level and not expiring soon.',
                        icon: Icons.check_circle_outline,
                      );
                    }
                    _syncEdits(suggestions);
                    final missing = suggestions.where(_needsSupplier).toList();
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (missing.isNotEmpty) ...[
                            _chooseSupplierCard(missing),
                            const SizedBox(height: 12),
                          ],
                          for (final suggestion in suggestions) ...[
                            _rowCard(suggestion),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
