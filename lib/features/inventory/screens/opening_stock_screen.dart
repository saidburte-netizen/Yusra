import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/permissions.dart';
import '../../../core/state/connectivity.dart';
import '../../../core/state/idempotency.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../data/reorder_models.dart';
import '../logic/opening_stock_csv.dart';
import '../widgets/responsive_ui.dart';
import '../widgets/stock_widgets.dart';

/// Bulk registration of stock that is already on the shelf. Every save goes
/// through a single all-or-nothing `add_opening_stock` RPC call.
class OpeningStockScreen extends ConsumerStatefulWidget {
  const OpeningStockScreen({super.key});

  @override
  ConsumerState<OpeningStockScreen> createState() => _OpeningStockScreenState();
}

class _OpeningRow {
  final quantity = TextEditingController(text: '1');
  final batchNo = TextEditingController();
  final unitCost = TextEditingController();
  Medicine? medicine;
  DateTime? expiry;

  void dispose() {
    quantity.dispose();
    batchNo.dispose();
    unitCost.dispose();
  }
}

class _OpeningStockScreenState extends ConsumerState<OpeningStockScreen> {
  final List<_OpeningRow> _rows = <_OpeningRow>[_OpeningRow()];
  final Set<int> _badRows = <int>{};
  bool _busy = false;
  String _submitKey = WriteIdempotency.newKey(Mutation.addOpeningStock);

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_OpeningRow()));

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      // Row indices shift after a removal, so all highlights are stale.
      _badRows.clear();
    });
  }

  void _resetRows() {
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..add(_OpeningRow());
    _badRows.clear();
  }

  String? _rowError(_OpeningRow row) {
    if (row.medicine == null) return 'Choose a medicine.';
    final quantity = int.tryParse(row.quantity.text.trim());
    if (quantity == null || quantity <= 0) {
      return 'Quantity must be a whole number above zero.';
    }
    final expiry = row.expiry;
    if (expiry == null) return 'Choose a future expiry date.';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    if (!expiryDay.isAfter(today)) {
      return 'Expired stock cannot be added; use write-off.';
    }
    final costText = row.unitCost.text.trim().replaceAll(',', '');
    final cost = costText.isEmpty ? 0.0 : double.tryParse(costText);
    if (cost == null || cost < 0) return 'Unit cost must not be negative.';
    return null;
  }

  OpeningStockRowInput _toInput(_OpeningRow row) {
    final batch = row.batchNo.text.trim();
    final costText = row.unitCost.text.trim().replaceAll(',', '');
    return OpeningStockRowInput(
      medicineId: row.medicine!.id,
      quantity: int.parse(row.quantity.text.trim()),
      expiry: row.expiry!,
      batchNo: batch.isEmpty ? null : batch,
      unitCost: double.tryParse(costText) ?? 0,
    );
  }

  Future<void> _save() async {
    final errors = <int, String>{};
    for (var i = 0; i < _rows.length; i++) {
      final error = _rowError(_rows[i]);
      if (error != null) errors[i] = error;
    }
    setState(() {
      _badRows
        ..clear()
        ..addAll(errors.keys);
    });
    if (errors.isNotEmpty) {
      final first = errors.entries.first;
      AppSnackbar.error(context, 'Row ${first.key + 1}: ${first.value}');
      return;
    }
    await _saveRows(_rows.map(_toInput).toList());
  }

  Future<void> _saveRows(List<OpeningStockRowInput> rows) async {
    if (rows.isEmpty) {
      AppSnackbar.error(context, 'Add at least one row.');
      return;
    }
    final branch = ref.read(branchScopeProvider);
    if (branch == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).addOpeningStock(
            branchId: branch,
            rows: rows,
            idempotencyKey: _submitKey,
          );
      if (!mounted) return;
      AppSnackbar.success(context, 'Saved ${rows.length} opening stock rows.');
      setState(() {
        _resetRows();
        _submitKey = WriteIdempotency.newKey(Mutation.addOpeningStock);
      });
      ref.applyMutation(Mutation.addOpeningStock);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _badRows.addAll(List<int>.generate(_rows.length, (index) => index));
      });
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        AppSnackbar.error(context,
            'Could not read the selected file. Please choose it again.');
      }
      return;
    }

    final parsed =
        OpeningStockCsv.parse(utf8.decode(bytes, allowMalformed: true));
    if (!mounted) return;
    final catalogue = await ref.read(inventoryRepositoryProvider).medicines();
    if (!mounted) return;
    final resolved = OpeningStockCsv.resolve(parsed.rows, catalogue);
    final inputs = [
      for (final match in resolved.rows)
        OpeningStockRowInput(
          medicineId: match.medicine.id,
          quantity: match.row.quantity,
          expiry: match.row.expiryDate ?? DateTime(2099),
          batchNo: match.row.batchNo.trim().isEmpty
              ? null
              : match.row.batchNo.trim(),
          unitCost: match.row.unitCost,
        ),
    ];

    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import preview'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogContentWidth(context, maxWidth: 520),
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${parsed.rows.length} valid of ${parsed.totalRows} rows'),
                if (parsed.errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Rows to fix:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final entry in parsed.errors.entries)
                    Text('Row ${entry.key}: ${entry.value}'),
                ],
                if (resolved.errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Medicines not found:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final entry in resolved.errors.entries)
                    Text('Row ${entry.key + 1}: ${entry.value}'),
                ],
                const SizedBox(height: 10),
                const Text('Ready to save:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final match in resolved.rows.take(12))
                  Text(
                    '${match.row.quantity} × ${match.medicine.name} — '
                    '${match.row.expiryDate == null ? '—' : formatDate(match.row.expiryDate!)}',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ResponsivePrimaryButton(
            label: 'Import ${inputs.length}',
            onPressed:
                inputs.isEmpty ? null : () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await _saveRows(inputs);
  }

  void _showTemplate() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Opening stock CSV template'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogContentWidth(context, maxWidth: 520),
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: SelectableText(OpeningStockCsv.template),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _shareTemplate,
            child: const Text('Share template'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareTemplate() async {
    // Byte-based XFile works on web as well as mobile: no dart:io File.
    final file = XFile.fromData(
      utf8.encode(OpeningStockCsv.template),
      mimeType: 'text/csv',
      name: 'yusra-opening-stock-template.csv',
    );
    await Share.shareXFiles(
      [file],
      subject: 'yusra-opening-stock-template.csv',
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final bad = _badRows.contains(index);
    return Card(
      shape: bad
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.danger),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Row ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: bad ? AppColors.danger : null,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _removeRow(index),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove row'),
                ),
              ],
            ),
            if (bad) ...[
              const SizedBox(height: 4),
              Text(
                'Fix the highlighted fields before saving.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
              const SizedBox(height: 8),
            ],
            SearchableSelect<Medicine>(
              label: 'Medicine',
              search: (query) =>
                  ref.read(inventoryRepositoryProvider).medicines(
                        query: query,
                        limit: query.trim().isEmpty ? 20 : 200,
                      ),
              display: medicineOptionLabel,
              value: row.medicine,
              onSelected: (value) => setState(() {
                row.medicine = value;
                _badRows.remove(index);
              }),
              onAddNew: (pickerContext) => addNewMedicine(pickerContext, ref),
              validator: (value) => value == null ? 'Choose a medicine.' : null,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;
                final width = stacked
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 36) / 4;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: AppTextField(
                        label: 'Quantity',
                        controller: row.quantity,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DatePickerField(
                        label: 'Expiry date',
                        value: row.expiry,
                        emptyText: 'Select expiry date',
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        onChanged: (date) => setState(() {
                          row.expiry = date;
                          _badRows.remove(index);
                        }),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: AppTextField(
                        label: 'Batch number (optional)',
                        controller: row.batchNo,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: AppTextField(
                        label: 'Unit cost (optional)',
                        controller: row.unitCost,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
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
        body: Center(child: Text('You do not have access to opening stock.')),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Opening stock',
                subtitle:
                    'Register stock already on the shelf — no supplier or purchase needed.',
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsiveSecondaryButton(
                      label: 'Import CSV',
                      icon: Icons.file_upload_outlined,
                      onPressed: _busy ? null : _importCsv,
                    ),
                  ),
                  ResponsiveSecondaryButton(
                    label: 'Download template',
                    icon: Icons.description_outlined,
                    onPressed: _showTemplate,
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _rows.length; i++) _rowCard(i),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ResponsiveSecondaryButton(
                            label: 'Add row',
                            icon: Icons.add,
                            onPressed: _addRow,
                          ),
                          ResponsivePrimaryButton(
                            label: 'Save all',
                            icon: Icons.save_outlined,
                            loading: _busy,
                            onPressed:
                                _rows.isEmpty || _busy || !writeEnabled(ref)
                                    ? null
                                    : _save,
                          ),
                        ],
                      ),
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
