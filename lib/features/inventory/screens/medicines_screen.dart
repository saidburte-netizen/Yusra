import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets.dart';
import '../data/inventory_ids.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../data/reorder_models.dart';
import '../logic/medicine_csv.dart';
import '../widgets/stock_widgets.dart';
import '../../../core/errors/app_error.dart';
import '../widgets/responsive_ui.dart';
import '../../pos/screens/pos_screen.dart' show posMedicinesProvider;

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
                    child: ResponsivePrimaryButton(
                      label: 'New medicine',
                      icon: Icons.add,
                      onPressed: () => _edit(null),
                    ),
                  ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsiveSecondaryButton(
                      label: 'Import CSV',
                      icon: Icons.file_upload_outlined,
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
                    data: (items) {
                      final value = _categoryId != null &&
                              !items.any((item) => item.id == _categoryId)
                          ? null
                          : _categoryId;
                      return AppDropdown<String?>(
                        label: 'Category',
                        value: value,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All')),
                          for (final item in items)
                            DropdownMenuItem(
                                value: item.id, child: Text(item.name)),
                        ],
                        onChanged: (next) => setState(() => _categoryId = next),
                      );
                    },
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
                      DropdownMenuItem(
                          value: 'inactive', child: Text('Inactive')),
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
                  child: ResponsiveDataTablePlus(
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
                            RowActions(actions: [
                              RowAction(
                                label: 'Details',
                                icon: Icons.open_in_new,
                                onSelected: () async {
                                  context.go('/inventory/medicines/${item.id}');
                                  return null;
                                },
                              ),
                              RowAction(
                                label: 'Edit',
                                icon: Icons.edit_outlined,
                                allowed: canEdit,
                                onSelected: () => _edit(item),
                              ),
                              RowAction(
                                label: item.isActive ? 'Deactivate' : 'Reactivate',
                                icon: item.isActive
                                    ? Icons.block_outlined
                                    : Icons.check_circle_outline,
                                allowed: canEdit,
                                confirmTitle: item.isActive
                                    ? 'Deactivate medicine'
                                    : 'Reactivate medicine',
                                confirmMessage:
                                    '${item.name} will ${item.isActive ? 'no longer' : 'again'} be available.',
                                onSelected: () => _toggleActive(item),
                                mutation: Mutation.saveMedicine,
                              ),
                              RowAction(
                                label: 'Delete',
                                icon: Icons.delete_outline,
                                allowed: canEdit,
                                danger: true,
                                confirmTitle: 'Delete medicine',
                                confirmMessage:
                                    'Delete ${item.name}? Medicines with stock or sales are deactivated instead.',
                                onSelected: () => _deleteMedicine(item),
                                mutation: Mutation.saveMedicine,
                              ),
                            ]),
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

  Future<String?> _edit(Medicine? medicine) async {
    final savedId =
        await showMedicineFormDialog(context, ref, initial: medicine);
    if (savedId == null) return null;
    ref.invalidate(medicinesProvider((query: _query, categoryId: _categoryId)));
    ref.invalidate(stockSummaryProvider);
    return 'Medicine saved.';
  }

  Future<String?> _toggleActive(Medicine medicine) async {
    await ref
        .read(inventoryRepositoryProvider)
        .setMedicineActive(medicine.id, !medicine.isActive);
    ref.invalidate(medicinesProvider((query: _query, categoryId: _categoryId)));
    return 'Medicine updated.';
  }

  /// Medicines with stock batches or sales lines are never hard deleted:
  /// deactivate them so history and audit stay intact.
  Future<String?> _deleteMedicine(Medicine medicine) async {
    final client = SupabaseService.client;
    final stock = await client
        .from('stock_batches')
        .select('id')
        .eq('medicine_id', medicine.id)
        .limit(1);
    final sales = await client
        .from('sale_items')
        .select('id')
        .eq('medicine_id', medicine.id)
        .limit(1);
    if ((stock as List).isNotEmpty || (sales as List).isNotEmpty) {
      if (!medicine.isActive) return 'Already inactive; history kept.';
      await ref
          .read(inventoryRepositoryProvider)
          .setMedicineActive(medicine.id, false);
      return 'Medicine has stock or sales history; deactivated instead of deleted.';
    }
    await client.from('medicines').delete().eq('id', medicine.id);
    return 'Medicine deleted.';
  }

  void _showTemplate() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Medicine CSV template'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogContentWidth(context, maxWidth: 520),
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            child: SelectableText(MedicineCsv.template),
          ),
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
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        AppSnackbar.error(context,
            'Could not read the selected file. Please choose it again.');
      }
      return;
    }
    final source = utf8.decode(bytes, allowMalformed: true);
    final parsed = MedicineCsv.parse(source);
    if (!mounted) return;
    final categories =
        ref.read(categoriesProvider).valueOrNull ?? const <Category>[];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import preview'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogContentWidth(context, maxWidth: 480),
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
          ResponsivePrimaryButton(
            label: 'Import ${parsed.rows.length}',
            onPressed:
                parsed.rows.isEmpty ? null : () => Navigator.pop(context, true),
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
            .where((item) =>
                item.name.toLowerCase() == row.categoryName.toLowerCase())
            .firstOrNull
            ?.id;
        await repository.saveMedicine(row.toJson(categoryId: categoryId));
        imported++;
      }
      if (!mounted) return;
      AppSnackbar.success(context, 'Imported $imported medicines.');
      ref.invalidate(
          medicinesProvider((query: _query, categoryId: _categoryId)));
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context,
            'Imported $imported before stopping. ${AppErrorMapper.from(e).message}');
      }
    }
  }
}

/// Shows the medicine registration/edit dialog.
///
/// Returns the saved medicine id, or null if cancelled.
Future<String?> showMedicineFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Medicine? initial,
}) {
  final supplierOptions = SupplierOption.load(ref);
  return showDialog<String?>(
    context: context,
    builder: (_) => _MedicineFormDialog(
      initial: initial,
      supplierOptions: supplierOptions,
    ),
  );
}

class _MedicineFormDialog extends ConsumerStatefulWidget {
  const _MedicineFormDialog({
    this.initial,
    required this.supplierOptions,
  });

  final Medicine? initial;
  final Future<List<SupplierOption>> supplierOptions;

  @override
  ConsumerState<_MedicineFormDialog> createState() =>
      _MedicineFormDialogState();
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
  late final TextEditingController _target;
  late final TextEditingController _storage;
  late final TextEditingController _quantity;
  DateTime _dateAdded = DateTime.now();
  String? _categoryId;
  String? _supplierId;
  bool _vat = false;
  bool _rx = false;
  bool _controlled = false;
  String? _imageUrl;
  bool _moreDetails = false;
  String? _lastSavedId;
  // New medicines need an id before the photo can be uploaded into its folder.
  late final String _newMedicineId = generateUuidV4();
  var _busy = false;

  bool get _isNew => widget.initial == null;

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
    _cost = TextEditingController(
        text: item == null ? '' : item.costPrice.toStringAsFixed(2));
    _price = TextEditingController(
        text: item == null ? '' : item.sellingPrice.toStringAsFixed(2));
    _reorder = TextEditingController(text: '${item?.reorderLevel ?? 10}');
    _target = TextEditingController(
        text: item?.targetLevel == null ? '' : '${item!.targetLevel}');
    _storage = TextEditingController(text: item?.storageNotes ?? '');
    _quantity = TextEditingController(text: '');
    _categoryId = item?.categoryId;
    _supplierId = item?.preferredSupplierId;
    _vat = item?.vatApplicable ?? false;
    _rx = item?.requiresPrescription ?? false;
    _controlled = item?.isControlled ?? false;
    _imageUrl = item?.imageUrl;
    _moreDetails = !_isNew;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _generic,
      _barcode,
      _form,
      _strength,
      _unit,
      _manufacturer,
      _cost,
      _price,
      _reorder,
      _target,
      _storage,
      _quantity,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final url =
          await ref.read(inventoryRepositoryProvider).uploadMedicineImage(
                widget.initial?.id ?? _newMedicineId,
                bytes,
                contentType: file.mimeType ?? 'image/png',
              );
      if (!mounted) return;
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCategory() async {
    final name = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add category'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogContentWidth(context, maxWidth: 400),
          ),
          child: Form(
            key: formKey,
            child: AppTextField(
              label: 'Category name',
              controller: name,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ResponsivePrimaryButton(
            label: 'Save',
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(inventoryRepositoryProvider).saveCategory({
        'name': name.text.trim(),
      });
      ref.invalidate(categoriesProvider);
      if (mounted) AppSnackbar.success(context, 'Category added.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  String _generateSku() {
    final base = _name.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final prefix =
        base.isEmpty ? 'MED' : (base.length > 8 ? base.substring(0, 8) : base);
    final suffix =
        DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return '$prefix-$suffix';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      final reorderLevel = int.tryParse(_reorder.text.trim()) ?? 10;
      final targetText = _target.text.trim();
      final targetLevel = targetText.isEmpty
          ? (widget.initial?.targetLevel != null ? null : reorderLevel * 2)
          : int.tryParse(targetText) ?? reorderLevel * 2;
      final cost = parseMoney(_cost.text) ?? 0;
      final price = parseMoney(_price.text) ?? 0;
      final qty = int.tryParse(_quantity.text.trim()) ?? 0;
      final id = widget.initial?.id ?? _newMedicineId;
      final sku = (widget.initial?.sku.trim().isNotEmpty ?? false)
          ? widget.initial!.sku
          : _generateSku();

      final payload = <String, dynamic>{
        'id': id,
        'name': _name.text.trim(),
        'sku': sku,
        'generic_name':
            _generic.text.trim().isEmpty ? null : _generic.text.trim(),
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'category_id': _categoryId,
        'dosage_form': _form.text.trim().isEmpty ? null : _form.text.trim(),
        'strength':
            _strength.text.trim().isEmpty ? null : _strength.text.trim(),
        'unit': _unit.text.trim().isEmpty ? 'Pack' : _unit.text.trim(),
        'manufacturer': _manufacturer.text.trim().isEmpty
            ? null
            : _manufacturer.text.trim(),
        'cost_price': cost,
        'selling_price': price,
        'reorder_level': reorderLevel,
        'preferred_supplier_id': _supplierId,
        'target_level': targetLevel,
        'storage_notes':
            _storage.text.trim().isEmpty ? null : _storage.text.trim(),
        'vat_applicable': _vat,
        'requires_prescription': _rx,
        'is_controlled': _controlled,
        'image_url': _imageUrl,
      };

      await repo.saveMedicine(payload, id: widget.initial?.id);

      if (_isNew && qty > 0) {
        final branchId = ref.read(branchScopeProvider);
        if (branchId == null) {
          throw Exception('Select a branch before adding opening stock.');
        }
        final expiry =
            DateTime(_dateAdded.year + 2, _dateAdded.month, _dateAdded.day);
        final batch =
            'OPENING-${_dateAdded.year.toString().padLeft(4, '0')}${_dateAdded.month.toString().padLeft(2, '0')}${_dateAdded.day.toString().padLeft(2, '0')}';
        await repo.addOpeningStock(
          branchId: branchId,
          rows: [
            OpeningStockRowInput(
              medicineId: id,
              quantity: qty,
              expiry: expiry,
              batchNo: batch,
              unitCost: cost,
            ),
          ],
        );
      }

      ref.invalidate(medicinesProvider);
      ref.invalidate(stockSummaryProvider);
      ref.invalidate(posMedicinesProvider);
      ref.invalidate(reorderSuggestionsProvider);

      if (!mounted) return;
      _lastSavedId = id;
      if (_isNew) {
        AppSnackbar.success(context, 'Medicine added with $qty in stock');
        Navigator.pop(context, id);
      } else {
        AppSnackbar.success(context, 'Medicine saved.');
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final isNew = _isNew;
    return AlertDialog(
      title: Text(isNew ? 'Add medicine' : 'Edit medicine'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogContentWidth(context, maxWidth: 680),
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pair(
                  AppTextField(
                    label: 'Medicine name',
                    controller: _name,
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  AppTextField(
                    label: 'Size / strength',
                    controller: _strength,
                  ),
                ),
                const SizedBox(height: 10),
                if (isNew)
                  _pair(
                    AppTextField(
                      label: 'Quantity',
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      validator: _wholeNumberValidator,
                    ),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dateAdded,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _dateAdded = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date added',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${_dateAdded.year}-${_dateAdded.month.toString().padLeft(2, '0')}-${_dateAdded.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                  ),
                if (isNew) const SizedBox(height: 10),
                _pair(
                  MoneyField(
                    label: 'Selling price',
                    controller: _price,
                    validator: (value) =>
                        (value == null || value <= 0) ? 'Required' : null,
                  ),
                  isNew
                      ? const SizedBox.shrink()
                      : MoneyField(
                          label: 'Cost price',
                          controller: _cost,
                          validator: (value) =>
                              (value ?? 0) >= 0 ? null : 'Invalid',
                        ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _moreDetails = !_moreDetails),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(_moreDetails
                            ? Icons.expand_less
                            : Icons.expand_more),
                        const SizedBox(width: 6),
                        const Text('More details',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                if (_moreDetails) ...[
                  const SizedBox(height: 6),
                  _pair(
                    AppTextField(
                      label: 'Generic name',
                      controller: _generic,
                    ),
                    _categoryField(categories),
                  ),
                  const SizedBox(height: 10),
                  _pair(
                    AppTextField(label: 'Barcode', controller: _barcode),
                    AppTextField(label: 'Form', controller: _form),
                  ),
                  const SizedBox(height: 10),
                  _pair(
                    AppTextField(label: 'Unit', controller: _unit),
                    AppTextField(
                        label: 'Manufacturer', controller: _manufacturer),
                  ),
                  const SizedBox(height: 10),
                  if (isNew)
                    MoneyField(
                      label: 'Cost price',
                      controller: _cost,
                      validator: (value) =>
                          (value ?? 0) >= 0 ? null : 'Invalid',
                    ),
                  if (isNew) const SizedBox(height: 10),
                  _pair(
                    AppTextField(
                      label: 'Reorder level',
                      controller: _reorder,
                      keyboardType: TextInputType.number,
                      validator: _wholeNumberValidator,
                    ),
                    AppTextField(
                      label: 'Target level (optional)',
                      controller: _target,
                      keyboardType: TextInputType.number,
                      validator: _wholeNumberValidator,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<SupplierOption>>(
                    future: widget.supplierOptions,
                    builder: (context, snapshot) {
                      final options = snapshot.data ?? const <SupplierOption>[];
                      final keepCurrent = _supplierId != null &&
                          !options.any((item) => item.id == _supplierId);
                      return AppDropdown<String?>(
                        label: 'Preferred supplier',
                        value: _supplierId,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          if (keepCurrent)
                            DropdownMenuItem(
                                value: _supplierId,
                                child: const Text('Current supplier')),
                          for (final supplier in options)
                            DropdownMenuItem(
                                value: supplier.id, child: Text(supplier.name)),
                        ],
                        onChanged: (value) =>
                            setState(() => _supplierId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  AppTextField(
                      label: 'Storage notes',
                      controller: _storage,
                      maxLines: 2),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('VAT applies'),
                    value: _vat,
                    onChanged: (value) => setState(() => _vat = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Requires prescription'),
                    value: _rx,
                    onChanged: (value) => setState(() => _rx = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Controlled drug'),
                    value: _controlled,
                    onChanged: (value) => setState(() => _controlled = value),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                        _imageUrl == null ? 'Upload photo' : 'Replace photo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _lastSavedId),
          child: Text(isNew ? 'Close' : 'Cancel'),
        ),
        ResponsivePrimaryButton(
          label: 'Save',
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _categoryField(List<Category> categories) {
    final value =
        categories.any((item) => item.id == _categoryId) ? _categoryId : null;
    return Row(
      children: [
        Expanded(
          child: AppDropdown<String?>(
            label: 'Category',
            value: value,
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final category in categories)
                DropdownMenuItem(
                    value: category.id, child: Text(category.name)),
            ],
            onChanged: (value) => setState(() => _categoryId = value),
          ),
        ),
        IconButton(
          tooltip: 'Add category',
          onPressed: _addCategory,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _pair(Widget left, Widget right) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 520) {
        return Column(children: [left, const SizedBox(height: 10), right]);
      }
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      );
    });
  }

  String? _wholeNumberValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null || n < 0) return 'Invalid number';
    return null;
  }
}
