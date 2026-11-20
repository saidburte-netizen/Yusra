import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/medicine_csv.dart';
import '../widgets/stock_widgets.dart';
import '../../../core/errors/app_error.dart';

class MedicinesScreen extends ConsumerStatefulWidget {
  const MedicinesScreen({super.key});

  @override
  ConsumerState<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends ConsumerState<MedicinesScreen> {
  final _search = TextEditingController();
  final _form = TextEditingController();
  String _query = '';
  String? _categoryId;
  String? _status;
  bool _rxOnly = false;

  @override
  void dispose() {
    _search.dispose();
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(medicinesProvider(
      (query: _query, categoryId: _categoryId),
    ));
    final categories = ref.watch(categoriesProvider);
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.medicines, PermAction.edit);
    final showCost = role != AppRole.cashier;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Medicines',
              subtitle: 'Catalogue, prices and prescription rules',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: 'New medicine',
                      icon: Icons.add,
                      width: 160,
                      onPressed: () => _edit(null),
                    ),
                  ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SecondaryButton(
                      label: 'Import CSV',
                      icon: Icons.file_upload_outlined,
                      width: 140,
                      onPressed: _importCsv,
                    ),
                  ),
                IconButton(
                  tooltip: 'CSV template and export',
                  onPressed: _showTemplate,
                  icon: const Icon(Icons.description_outlined),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: AppTextField(
                    label: 'Search name, generic name, barcode or SKU',
                    controller: _search,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: categories.when(
                    data: (items) => AppDropdown<String?>(
                      label: 'Category',
                      value: _categoryId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        for (final item in items)
                          DropdownMenuItem(value: item.id, child: Text(item.name)),
                      ],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                    loading: () => const SizedBox(height: 56),
                    error: (_, __) => const SizedBox(height: 56),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: AppTextField(
                    label: 'Dosage form',
                    controller: _form,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: AppDropdown<String?>(
                    label: 'Status',
                    value: _status,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
                FilterChip(
                  label: const Text('Rx only'),
                  selected: _rxOnly,
                  onSelected: (value) => setState(() => _rxOnly = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            stockState(
              state,
              onRetry: () => ref.invalidate(medicinesProvider(
                (query: _query, categoryId: _categoryId),
              )),
              builder: (items) {
                final visible = items.where((item) {
                  if (_status == 'active' && !item.isActive) return false;
                  if (_status == 'inactive' && item.isActive) return false;
                  if (_rxOnly && !item.requiresPrescription) return false;
                  if (_form.text.isNotEmpty &&
                      !(item.dosageForm ?? '')
                          .toLowerCase()
                          .contains(_form.text.toLowerCase())) {
                    return false;
                  }
                  return true;
                }).toList();
                return Expanded(
                  child: DataTablePlus(
                    columns: [
                      'Name',
                      'SKU / barcode',
                      'Category',
                      'Form',
                      if (showCost) 'Cost',
                      'Price',
                      'Reorder',
                      'Status',
                      '',
                    ],
                    rows: [
                      for (final item in visible)
                        DataTablePlusRow(
                          cells: [
                            item.name,
                            '${item.sku}${item.barcode == null ? '' : ' / ${item.barcode}'}',
                            _categoryName(categories.value, item.categoryId),
                            item.dosageForm ?? '—',
                            if (showCost) formatMoney(item.costPrice),
                            formatMoney(item.sellingPrice),
                            '${item.reorderLevel}',
                            item.isActive ? 'Active' : 'Inactive',
                            '',
                          ],
                          actions: [
                            IconButton(
                              tooltip: 'Details',
                              icon: const Icon(Icons.open_in_new, size: 18),
                              onPressed: () => context
                                  .go('/inventory/medicines/${item.id}'),
                            ),
                            if (canEdit)
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _edit(item),
                              ),
                            if (canEdit)
                              IconButton(
                                tooltip: item.isActive ? 'Deactivate' : 'Reactivate',
                                icon: Icon(
                                  item.isActive
                                      ? Icons.block_outlined
                                      : Icons.check_circle_outline,
                                  size: 18,
                                ),
                                onPressed: () => _toggleActive(item),
                              ),
                          ],
                        ),
                    ],
                    filterChips: const ['Rx', 'Controlled'],
                    selectedFilter: _rxOnly ? 'Rx' : null,
                    onFilterChanged: (value) =>
                        setState(() => _rxOnly = value == 'Rx'),
                    exportFileName: 'yusra-medicines.csv',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _categoryName(List<Category>? categories, String? id) {
    if (id == null) return '—';
    return categories?.where((item) => item.id == id).firstOrNull?.name ?? '—';
  }

  Future<void> _edit(Medicine? medicine) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MedicineFormDialog(initial: medicine),
    );
    if (result == null) return;
    try {
      await ref.read(inventoryRepositoryProvider).saveMedicine(
            result,
            id: medicine?.id,
          );
      if (!mounted) return;
      AppSnackbar.success(context, 'Medicine saved.');
      ref.invalidate(medicinesProvider((query: _query, categoryId: _categoryId)));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _toggleActive(Medicine medicine) async {
    final confirm = await showConfirmDialog(
      context,
      title: medicine.isActive ? 'Deactivate medicine' : 'Reactivate medicine',
      message: '${medicine.name} will ${medicine.isActive ? 'no longer' : 'again'} be available.',
    );
    if (confirm != true) return;
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .setMedicineActive(medicine.id, !medicine.isActive);
      if (!mounted) return;
      AppSnackbar.success(context, 'Medicine updated.');
      ref.invalidate(medicinesProvider((query: _query, categoryId: _categoryId)));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  void _showTemplate() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Medicine CSV template'),
        content: SizedBox(
          width: 520,
          child: SelectableText(MedicineCsv.template),
        ),
        actions: [
          TextButton(
            onPressed: () => Share.share(MedicineCsv.template,
                subject: 'yusra-medicines-template.csv'),
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

  Future<void> _importCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final source = file.bytes != null
        ? String.fromCharCodes(file.bytes!)
        : await File(file.path!).readAsString();
    final parsed = MedicineCsv.parse(source);
    if (!mounted) return;
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import preview'),
        content: SizedBox(
          width: 480,
          height: 420,
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
                const SizedBox(height: 10),
                const Text('Valid medicines:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final row in parsed.rows.take(12))
                  Text('${row.name} — ${formatMoney(row.sellingPrice)}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            label: 'Import ${parsed.rows.length}',
            width: 150,
            onPressed: parsed.rows.isEmpty
                ? null
                : () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final repository = ref.read(inventoryRepositoryProvider);
    var imported = 0;
    try {
      for (final row in parsed.rows) {
        final categoryId = categories
            .where((item) => item.name.toLowerCase() == row.categoryName.toLowerCase())
            .firstOrNull
            ?.id;
        await repository.saveMedicine(row.toJson(categoryId: categoryId));
        imported++;
      }
      if (!mounted) return;
      AppSnackbar.success(context, 'Imported $imported medicines.');
      ref.invalidate(medicinesProvider((query: _query, categoryId: _categoryId)));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Imported $imported before stopping. ${AppErrorMapper.from(e).message}');
    }
  }
}

class _MedicineFormDialog extends ConsumerStatefulWidget {
  const _MedicineFormDialog({this.initial});

  final Medicine? initial;

  @override
  ConsumerState<_MedicineFormDialog> createState() => _MedicineFormDialogState();
}

class _MedicineFormDialogState extends ConsumerState<_MedicineFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _generic;
  late final TextEditingController _barcode;
  late final TextEditingController _form;
  late final TextEditingController _strength;
  late final TextEditingController _unit;
  late final TextEditingController _manufacturer;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _reorder;
  late final TextEditingController _storage;
  String? _categoryId;
  bool _vat = false;
  bool _rx = false;
  bool _controlled = false;
  String? _imageUrl;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _name = TextEditingController(text: item?.name ?? '');
    _generic = TextEditingController(text: item?.genericName ?? '');
    _barcode = TextEditingController(text: item?.barcode ?? '');
    _form = TextEditingController(text: item?.dosageForm ?? '');
    _strength = TextEditingController(text: item?.strength ?? '');
    _unit = TextEditingController(text: item?.unit ?? 'Pack');
    _manufacturer = TextEditingController(text: item?.manufacturer ?? '');
    _cost = TextEditingController(text: '${item?.costPrice ?? 0}');
    _price = TextEditingController(text: '${item?.sellingPrice ?? 0}');
    _reorder = TextEditingController(text: '${item?.reorderLevel ?? 10}');
    _storage = TextEditingController(text: item?.storageNotes ?? '');
    _categoryId = item?.categoryId;
    _vat = item?.vatApplicable ?? false;
    _rx = item?.requiresPrescription ?? false;
    _controlled = item?.isControlled ?? false;
    _imageUrl = item?.imageUrl;
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _generic, _barcode, _form, _strength, _unit,
      _manufacturer, _cost, _price, _reorder, _storage,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null || widget.initial == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await ref
          .read(inventoryRepositoryProvider)
          .uploadMedicineImage(widget.initial!.id, bytes);
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    return AlertDialog(
      title: Text(widget.initial == null ? 'New medicine' : 'Edit medicine'),
      content: SizedBox(
        width: 560,
        height: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: _name,
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                AppTextField(label: 'Generic name', controller: _generic),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(label: 'Barcode', controller: _barcode)),
                    const SizedBox(width: 8),
                    BarcodeScanButton(
                      compact: true,
                      onDetected: (code) => setState(() => _barcode.text = code),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppDropdown<String?>(
                  label: 'Category',
                  value: _categoryId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final category in categories)
                      DropdownMenuItem(value: category.id, child: Text(category.name)),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(label: 'Dosage form', controller: _form)),
                    const SizedBox(width: 10),
                    Expanded(child: AppTextField(label: 'Strength', controller: _strength)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AppTextField(label: 'Unit', controller: _unit)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(label: 'Manufacturer', controller: _manufacturer),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MoneyField(
                        label: 'Cost price',
                        controller: _cost,
                        validator: (value) => (value ?? 0) >= 0 ? null : 'Invalid',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MoneyField(
                        label: 'Selling price',
                        controller: _price,
                        validator: (value) => (value ?? 0) >= 0 ? null : 'Invalid',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(
                  label: 'Reorder level',
                  controller: _reorder,
                  keyboardType: TextInputType.number,
                  validator: (value) => (int.tryParse(value ?? '') ?? -1) >= 0
                      ? null
                      : 'Whole number required',
                ),
                const SizedBox(height: 10),
                AppTextField(label: 'Storage notes', controller: _storage, maxLines: 2),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    SwitchListTile(
                      title: const Text('VAT applies'),
                      value: _vat,
                      onChanged: (value) => setState(() => _vat = value),
                    ),
                    SwitchListTile(
                      title: const Text('Requires prescription'),
                      value: _rx,
                      onChanged: (value) => setState(() => _rx = value),
                    ),
                    SwitchListTile(
                      title: const Text('Controlled drug'),
                      value: _controlled,
                      onChanged: (value) => setState(() => _controlled = value),
                    ),
                  ],
                ),
                if (widget.initial != null)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_imageUrl == null ? 'Upload photo' : 'Replace photo'),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        PrimaryButton(
          label: 'Save',
          width: 120,
          loading: _busy,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'generic_name': _generic.text.trim().isEmpty ? null : _generic.text.trim(),
              'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
              'category_id': _categoryId,
              'dosage_form': _form.text.trim().isEmpty ? null : _form.text.trim(),
              'strength': _strength.text.trim().isEmpty ? null : _strength.text.trim(),
              'unit': _unit.text.trim().isEmpty ? 'Pack' : _unit.text.trim(),
              'manufacturer':
                  _manufacturer.text.trim().isEmpty ? null : _manufacturer.text.trim(),
              'cost_price': parseMoney(_cost.text) ?? 0,
              'selling_price': parseMoney(_price.text) ?? 0,
              'reorder_level': int.parse(_reorder.text),
              'storage_notes': _storage.text.trim().isEmpty ? null : _storage.text.trim(),
              'vat_applicable': _vat,
              'requires_prescription': _rx,
              'is_controlled': _controlled,
              'image_url': _imageUrl,
            });
          },
        ),
      ],
    );
  }
}
