import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/money.dart';
import '../../../core/permissions.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../sales/data/sales.dart';
import '../../sales/logic/receipts.dart';
import '../../../core/errors/app_error.dart';
import '../../inventory/widgets/responsive_ui.dart';

class ShiftsScreen extends ConsumerStatefulWidget {
  const ShiftsScreen({super.key});

  @override
  ConsumerState<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends ConsumerState<ShiftsScreen> {
  bool _openOnly = false;
  bool _busy = false;

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
      ref.invalidate(shiftsProvider);
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
    final countController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Opened ${formatDateTime(shift.openedAt ?? DateTime.now())}'),
            const SizedBox(height: 8),
            Text('Opening cash ${formatMoney(shift.openingCash)}'),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Counted cash (ETB)',
              controller: countController,
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
    final counted = double.tryParse(countController.text.replaceAll(',', ''));
    if (counted == null) {
      AppSnackbar.error(context, 'Enter the counted cash.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(salesRepositoryProvider).closeShift(
            shift.id,
            counted,
            noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
          );
      ref.invalidate(myOpenShiftProvider);
      ref.invalidate(shiftsProvider);
      final settings = await ref.read(receiptSettingsProvider.future);
      final profile = ref.read(authProvider).profile;
      final branchName = await _branchName();
      await Receipts.printShiftReport(
        title: 'Z',
        settings: settings,
        branchName: branchName,
        cashierName: shift.cashierName ?? profile?.fullName ?? '',
        shift: shift.copyWith(
          closedAt: DateTime.now(),
          closingCash: result.closingCash,
          expectedCash: result.expectedCash,
          difference: result.difference,
          status: 'closed',
        ),
        saleCount:
            await ref.read(salesRepositoryProvider).shiftSaleCount(shift.id),
        byMethod: await _byMethod(shift.id),
        expectedCash: result.expectedCash,
        closingCash: result.closingCash,
        difference: result.difference,
      );
      if (mounted) {
        AppSnackbar.success(
          context,
          'Shift closed. Difference ${formatMoney(result.difference)}.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _xReport(Shift shift) async {
    try {
      final settings = await ref.read(receiptSettingsProvider.future);
      final profile = ref.read(authProvider).profile;
      await Receipts.printShiftReport(
        title: 'X',
        settings: settings,
        branchName: await _branchName(),
        cashierName: shift.cashierName ?? profile?.fullName ?? '',
        shift: shift,
        saleCount:
            await ref.read(salesRepositoryProvider).shiftSaleCount(shift.id),
        byMethod: await _byMethod(shift.id),
        expectedCash: shift.expectedCash ?? shift.openingCash,
      );
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  Future<String> _branchName() async {
    if (!SupabaseService.isReady) return 'Main branch';
    final id = ref.read(branchScopeProvider);
    if (id == null) return 'All branches';
    try {
      final row = await SupabaseService.client
          .from('branches')
          .select('name')
          .eq('id', id)
          .single();
      return row['name'] as String? ?? 'Main branch';
    } catch (_) {
      return 'Main branch';
    }
  }

  Future<Map<String, double>> _byMethod(String shiftId) async {
    if (!SupabaseService.isReady) return {};
    final rows = await SupabaseService.client
        .from('sales')
        .select('sale_payments!sale_payments_sale_id_fkey(method, amount)')
        .eq('shift_id', shiftId)
        .eq('status', 'completed') as List;
    final result = <String, double>{};
    for (final row in rows) {
      final payments = (row as Map)['sale_payments'];
      if (payments is! List) continue;
      for (final payment in payments) {
        if (payment is! Map) continue;
        final method = payment['method'] as String? ?? 'cash';
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
        result[method] = (result[method] ?? 0) + amount;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile;
    final role = profile?.role ?? AppRole.cashier;
    final myShift = ref.watch(myOpenShiftProvider);
    final shifts = ref.watch(shiftsProvider(_openOnly));
    final canViewAll = !isOwnOnly(role, Modules.shifts);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Cash shifts',
              subtitle: 'Open, close and reconcile cash drawer shifts',
              actions: [
                if (can(role, Modules.pos, PermAction.edit))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ResponsivePrimaryButton(
                      label: _busy ? 'Working…' : 'Start shift',
                      icon: Icons.play_arrow,
                      loading: _busy,
                      onPressed: _openShift,
                    ),
                  ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () {
                    ref.invalidate(shiftsProvider);
                    ref.invalidate(myOpenShiftProvider);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            myShift.when(
              data: (shift) {
                if (shift == null) return const SizedBox.shrink();
                return Card(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkElevated
                      : AppColors.pink50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.point_of_sale,
                                color: AppColors.pink600),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Your open shift',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      'Opened ${formatDateTime(shift.openedAt ?? DateTime.now())}'
                                      '  •  Opening cash ${formatMoney(shift.openingCash)}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ResponsiveSecondaryButton(
                              label: 'X report',
                              icon: Icons.receipt_long,
                              onPressed: () => _xReport(shift),
                            ),
                            ResponsivePrimaryButton(
                              label: 'Close shift',
                              icon: Icons.stop,
                              onPressed:
                                  _busy ? null : () => _closeShift(shift),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const ResponsiveLoadingSkeleton(lines: 1),
              error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(myOpenShiftProvider)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All shifts'),
                  selected: !_openOnly,
                  onSelected: (_) => setState(() => _openOnly = false),
                ),
                ChoiceChip(
                  label: const Text('Open only'),
                  selected: _openOnly,
                  onSelected: (_) => setState(() => _openOnly = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: shifts.when(
                data: (rows) {
                  final visible = canViewAll
                      ? rows
                      : rows
                          .where((row) => row.cashierId == profile?.id)
                          .toList();
                  if (visible.isEmpty) {
                    return const EmptyState(
                      message: 'No shifts yet. Start a shift to begin selling.',
                      icon: Icons.schedule,
                    );
                  }
                  return ResponsiveDataTablePlus(
                    columns: const [
                      'Shift',
                      'Cashier',
                      'Opened',
                      'Opening',
                      'Closing',
                      'Expected',
                      'Difference',
                      'Status',
                    ],
                    rows: [
                      for (final shift in visible)
                        DataTablePlusRow(
                          cells: [
                            shift.id.length >= 8
                                ? shift.id.substring(0, 8)
                                : shift.id,
                            shift.cashierName ?? '—',
                            shift.openedAt == null
                                ? '—'
                                : formatDateTime(shift.openedAt!),
                            formatMoney(shift.openingCash),
                            shift.closingCash == null
                                ? '—'
                                : formatMoney(shift.closingCash!),
                            shift.expectedCash == null
                                ? '—'
                                : formatMoney(shift.expectedCash!),
                            shift.difference == null
                                ? '—'
                                : formatMoney(shift.difference!),
                            shift.status.toUpperCase(),
                          ],
                          actions: [
                            if (shift.isOpen)
                              IconButton(
                                tooltip: 'X report',
                                icon: const Icon(Icons.print_outlined),
                                onPressed: () => _xReport(shift),
                              ),
                            RowActions(actions: [
                              RowAction(
                                label: 'View',
                                icon: Icons.visibility_outlined,
                                onSelected: () async {
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: Text('Shift ${shift.id.substring(0, 8)}'),
                                      content: Text(
                                          '${shift.cashierName ?? '—'} · ${shift.status} · opened ${shift.openedAt == null ? '—' : formatDateTime(shift.openedAt!)}'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Close'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return null;
                                },
                              ),
                              RowAction(
                                label: 'Close shift',
                                icon: Icons.lock_outline,
                                allowed: shift.isOpen &&
                                    (can(role, Modules.shifts, PermAction.edit) ||
                                        (isOwnOnly(role, Modules.shifts) &&
                                            shift.cashierId == profile?.id)),
                                danger: false,
                                onSelected: () async {
                                  await _closeShift(shift);
                                  return null;
                                },
                                mutation: Mutation.closeShift,
                              ),
                            ]),
                          ],
                        ),
                    ],
                    searchHint: 'Search shifts…',
                    exportFileName: 'yusra-shifts.csv',
                  );
                },
                loading: () => const ResponsiveLoadingSkeleton(lines: 4),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(shiftsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
