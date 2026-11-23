import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/permissions.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../logic/stock_rules.dart';
import '../../../core/errors/app_error.dart';
import '../widgets/responsive_ui.dart';

/// B9 — device-persisted stock take with live variance and RPC-backed apply.
///
/// Applying a saved draft always posts every non-zero variance in the visible
/// category in one pass; a "save/apply partial" mode is n/a by design because
/// a stock take is a complete count of the selected scope. The device draft
/// can be saved or discarded, but is never written to the database as a row.
class StocktakeScreen extends ConsumerStatefulWidget {
  const StocktakeScreen({super.key});

  @override
  ConsumerState<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends ConsumerState<StocktakeScreen> {
  static const _draftKey = 'yusra.stocktake.draft';

  String? _branchId;
  String? _categoryId;
  List<StockBatch> _batches = const [];
  Map<String, Medicine> _medicines = const {};
  List<Map<String, dynamic>> _branches = const [];
  final Map<String, TextEditingController> _counts = {};
  bool _loading = true;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = ref.read(branchScopeProvider);
    _load();
  }

  @override
  void dispose() {
    for (final controller in _counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    if (!SupabaseService.isReady) return;
    final profile = ref.read(authProvider).profile;
    if (profile != null && !canSeeAllBranches(profile.role)) return;
    final rows =
        await SupabaseService.client.from('branches').select('id,name');
    setState(() => _branches = List<Map<String, dynamic>>.from(rows as List));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadBranches();
      final repo = ref.read(inventoryRepositoryProvider);
      final batches = await repo.batches(branchId: _branchId);
      final medicines = await repo.medicines();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      Map<String, dynamic> draft = const {};
      if (raw != null) {
        try {
          draft = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          draft = {};
        }
      }
      for (final controller in _counts.values) {
        controller.dispose();
      }
      _counts.clear();
      for (final batch in batches) {
        final initial = draft[batch.id] ?? batch.quantity;
        _counts[batch.id] = TextEditingController(text: initial.toString());
      }
      setState(() {
        _batches = batches;
        _medicines = {for (final medicine in medicines) medicine.id: medicine};
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = <String, int>{
      for (final entry in _counts.entries)
        entry.key: int.tryParse(entry.value.text) ?? 0,
    };
    await prefs.setString(_draftKey, jsonEncode(draft));
  }

  /// Removes the locally saved counts and resets every field to the system
  /// quantity. This is a real delete of the device draft (not a DB row): the
  /// stock take is a counting worksheet, so no draft table exists server-side.
  Future<void> _discardDraft() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Discard draft?',
      message: 'The saved counts on this device will be removed and all '
          'fields reset to the current system quantities.',
      confirmLabel: 'Discard draft',
    );
    if (confirm != true || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      final systemQty = {
        for (final batch in _batches) batch.id: batch.quantity
      };
      for (final entry in _counts.entries) {
        entry.value.text = '${systemQty[entry.key] ?? 0}';
      }
      if (!mounted) return;
      setState(() {});
      AppSnackbar.success(context, 'Draft discarded.');
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(e).message);
      }
    }
  }

  List<StockBatch> get _visibleBatches {
    if (_categoryId == null) return _batches;
    return _batches.where((batch) {
      return _medicines[batch.medicineId]?.categoryId == _categoryId;
    }).toList();
  }

  int _counted(String id) => int.tryParse(_counts[id]?.text ?? '') ?? 0;

  int get _varianceLines => _visibleBatches.where((batch) {
        return StockRules.variance(
              counted: _counted(batch.id),
              systemQty: batch.quantity,
            ) !=
            0;
      }).length;

  Future<void> _apply() async {
    final role = ref.read(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.stock, PermAction.edit)) {
      AppSnackbar.error(context, 'You cannot apply stock adjustments.');
      return;
    }
    if (_varianceLines == 0) {
      AppSnackbar.error(context, 'No variances to apply.');
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: 'Apply stock take',
      message: 'Apply $_varianceLines variance(s)? Each one creates an '
          'adjustment with reason "Stock take".',
    );
    if (confirm != true) return;
    setState(() => _applying = true);
    final reason = 'Stock take ${formatIsoDate(DateTime.now())}';
    var applied = 0;
    try {
      final repo = ref.read(inventoryRepositoryProvider);
      for (final batch in _visibleBatches) {
        final change = StockRules.adjustmentFor(
          counted: _counted(batch.id),
          systemQty: batch.quantity,
        );
        if (change == 0) continue;
        await repo.adjustStock(
          batchId: batch.id,
          change: change,
          type: 'adjustment',
          reason: reason,
        );
        applied++;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      if (!mounted) return;
      AppSnackbar.success(context, 'Applied $applied adjustment(s).');
      ref.invalidate(stockSummaryProvider);
      ref.invalidate(batchesProvider(null));
      ref.invalidate(movementsProvider((medicineId: null, type: null)));
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canApply = can(role, Modules.stock, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Stock take',
              subtitle: 'Count each batch and apply the variance',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ResponsiveSecondaryButton(
                    label: 'Save draft',
                    icon: Icons.save_outlined,
                    onPressed: _loading
                        ? null
                        : () async {
                            await _saveDraft();
                            if (!context.mounted) return;
                            AppSnackbar.success(
                                context, 'Draft saved on this device.');
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ResponsiveSecondaryButton(
                    label: 'Discard draft',
                    icon: Icons.delete_outline,
                    onPressed: _loading ? null : _discardDraft,
                  ),
                ),
                ResponsivePrimaryButton(
                  label: 'Apply $_varianceLines variance(s)',
                  icon: Icons.check_circle_outline,
                  loading: _applying,
                  onPressed: canApply && !_loading ? _apply : null,
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                          width: constraints.maxWidth < 600
                              ? constraints.maxWidth
                              : 220,
                          child: _branches.isEmpty
                              ? AppTextField(
                                  label: 'Branch',
                                  controller: TextEditingController(
                                    text: _branchId ?? 'Current branch',
                                  ),
                                  enabled: false,
                                )
                              : AppDropdown<String?>(
                                  label: 'Branch',
                                  value: _branchId,
                                  items: [
                                    for (final branch in _branches)
                                      DropdownMenuItem<String>(
                                        value: branch['id'] as String?,
                                        child: Text(
                                            (branch['name'] as String?) ?? '—'),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    setState(() => _branchId = value);
                                    _load();
                                  },
                                ),
                        )),
                LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                          width: constraints.maxWidth < 600
                              ? constraints.maxWidth
                              : 220,
                          child: AppDropdown<String?>(
                            label: 'Category (optional)',
                            value: _categoryId,
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('All')),
                              for (final category in categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _categoryId = value),
                          ),
                        )),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: ErrorState(message: _error!, onRetry: _load))
            else if (_visibleBatches.isEmpty)
              const Expanded(
                child: EmptyState(
                  message: 'No batches in this branch and category.',
                  icon: Icons.inventory_2_outlined,
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(1),
                      4: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: Color(0xFFF7F7F8)),
                        children: [
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Medicine / batch',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Expiry',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('System',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Counted',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Variance',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      for (final batch in _visibleBatches)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                '${_medicines[batch.medicineId]?.name ?? batch.medicineName ?? batch.medicineId}\n'
                                '${batch.batchNo}',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(formatDate(batch.expiryDate)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text('${batch.quantity}'),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _counts[batch.id],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                '${StockRules.variance(counted: _counted(batch.id), systemQty: batch.quantity) >= 0 ? '+' : ''}'
                                '${StockRules.variance(counted: _counted(batch.id), systemQty: batch.quantity)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: StockRules.variance(
                                              counted: _counted(batch.id),
                                              systemQty: batch.quantity) ==
                                          0
                                      ? null
                                      : Colors.orange.shade800,
                                ),
                              ),
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
    );
  }
}
