import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/state/app_cache.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';

class _ReportDef {
  const _ReportDef({
    required this.title,
    required this.view,
    required this.columns,
    this.dateKey,
  });

  final String title;
  final String view;
  final List<String> columns;
  final String? dateKey;
}

/// Each report reads a dedicated Supabase view. Views are the single source of
/// truth for aggregation so the app never recomputes financial figures in Dart.
const List<_ReportDef> _reports = [
  _ReportDef(
    title: S.salesByDay,
    view: 'v_report_sales_by_day',
    columns: ['date', 'invoices', 'gross', 'discounts', 'vat', 'net'],
    dateKey: 'date',
  ),
  _ReportDef(title: S.salesByCashier, view: 'v_report_sales_by_cashier',
      columns: ['cashier', 'invoices', 'total']),
  _ReportDef(title: S.salesByPaymentMethod, view: 'v_report_sales_payment',
      columns: ['payment_method', 'invoices', 'total']),
  _ReportDef(title: S.salesByMedicine, view: 'v_report_sales_by_medicine',
      columns: ['medicine', 'qty', 'revenue', 'cost', 'profit']),
  _ReportDef(
    title: S.profitReport,
    view: 'v_report_profit',
    columns: ['date', 'revenue', 'cost', 'profit', 'margin'],
    dateKey: 'date',
  ),
  _ReportDef(title: S.stockValuation, view: 'v_report_stock_valuation',
      columns: ['medicine', 'qty', 'unit_cost', 'value']),
  _ReportDef(
    title: S.expiryLosses,
    view: 'v_report_expiry_losses',
    columns: ['expiry', 'medicine', 'batch', 'qty', 'value'],
    dateKey: 'expiry',
  ),
  _ReportDef(title: S.purchasesBySupplier, view: 'v_report_purchases_supplier',
      columns: ['supplier', 'orders', 'total']),
  _ReportDef(
    title: S.expensesReport,
    view: 'v_report_expenses',
    columns: ['date', 'category', 'amount'],
    dateKey: 'date',
  ),
  _ReportDef(title: S.netProfit, view: 'v_report_net_profit',
      columns: ['period', 'revenue', 'expenses', 'net']),
  _ReportDef(title: S.shiftVariance, view: 'v_report_shift_variance',
      columns: ['cashier', 'shift', 'expected', 'actual', 'variance']),
  _ReportDef(title: S.controlledRegister, view: 'v_report_controlled_register',
      columns: ['date', 'medicine', 'qty', 'prescriber', 'patient'],
      dateKey: 'date'),
];

const Set<String> _moneyKeys = {
  'gross', 'discounts', 'vat', 'net', 'total', 'revenue', 'cost', 'profit',
  'margin', 'unit_cost', 'value', 'amount', 'expenses', 'expected', 'actual',
  'variance',
};

/// The reports are backed by views that are not part of the base schema.
const String _viewsHint =
    'If the report views are missing, apply '
    'supabase/migrations/0014_report_views.sql in the Supabase SQL Editor and '
    'try again.';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _selected = 0;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  DateTime? _from;
  DateTime? _to;

  _ReportDef get _report => _reports[_selected];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final report = _report;
      var query = SupabaseService.client.from(report.view).select();
      if (report.dateKey != null) {
        if (_from != null) {
          query = query.gte(
              report.dateKey!, startOfAddisDayUtc(_from!).toIso8601String());
        }
        if (_to != null) {
          query = query.lte(
            report.dateKey!,
            endOfAddisDayUtc(_to!).toIso8601String(),
          );
        }
      }
      final result = await query.limit(1000);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(result as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${AppErrorMapper.from(e).message}\n\n$_viewsHint';
        _loading = false;
      });
    }
  }

  /// Clears any cached report data before re-running the query so a retry
  /// after applying the migration actually reflects the new views.
  Future<void> _retry() async {
    ref.invalidateCache(CacheTag.reports);
    await _load();
  }

  void _select(int index) {
    setState(() {
      _selected = index;
      _from = null;
      _to = null;
    });
    _load();
  }

  String _cell(String key, dynamic value) {
    if (value == null) return '—';
    if (_moneyKeys.contains(key)) {
      final number = value is num ? value : num.tryParse(value.toString());
      return number == null ? value.toString() : formatMoney(number);
    }
    if (key == 'date' || key == 'expiry') {
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return formatDate(parsed);
      }
    }
    return value.toString();
  }

  List<List<dynamic>> _csvRows() {
    final header = [for (final key in _report.columns) _label(key)];
    return [
      header,
      for (final row in _rows)
        [for (final key in _report.columns) _cell(key, row[key])],
    ];
  }

  String _label(String key) {
    final words = key.replaceAll('_', ' ');
    if (words.isEmpty) return key;
    return words[0].toUpperCase() + words.substring(1);
  }

  Future<void> _exportPdf() async {
    try {
      final document = pw.Document();
      final tableRows = _csvRows();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('${S.appName} — ${_report.title}'),
            ),
            pw.Text(
              '${S.period}: ${_from == null ? S.all : formatDate(_from!)} — '
              '${_to == null ? S.all : formatDate(_to!)}',
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: tableRows.first.map((e) => e.toString()).toList(),
              data: tableRows.skip(1).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.pink50),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: const pw.TextStyle(fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      );
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'yusra-${_report.view}.pdf',
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.reports, PermAction.view)) {
      return const Scaffold(body: Center(child: Text(S.forbiddenBody)));
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.reports,
              subtitle: _report.title,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: _rows.isEmpty ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text(S.exportPdf),
                  ),
                ),
                IconButton(onPressed: _retry, icon: const Icon(Icons.refresh)),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: Card(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) => ListTile(
                          dense: true,
                          selected: index == _selected,
                          selectedColor: AppColors.pink600,
                          leading: CircleAvatar(
                            radius: 13,
                            backgroundColor: index == _selected
                                ? AppColors.pink600
                                : AppColors.pink50,
                            child: Text('${index + 1}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: index == _selected
                                        ? AppColors.white
                                        : AppColors.pink600)),
                          ),
                          title: Text(_reports[index].title),
                          onTap: () => _select(index),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        if (_report.dateKey != null)
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: 170,
                                child: DatePickerField(
                                  label: S.dateFrom,
                                  value: _from,
                                  onChanged: (value) {
                                    setState(() => _from = value);
                                    _load();
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: DatePickerField(
                                  label: S.dateTo,
                                  value: _to,
                                  onChanged: (value) {
                                    setState(() => _to = value);
                                    _load();
                                  },
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _from = null;
                                    _to = null;
                                  });
                                  _load();
                                },
                                icon: const Icon(Icons.filter_alt_off_outlined),
                                label: const Text(S.reset),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Expanded(
                              child: Center(child: CircularProgressIndicator()))
                        else if (_error != null)
                          Expanded(child: ErrorState(message: _error!, onRetry: _retry))
                        else
                          Expanded(
                            child: DataTablePlus(
                              columns: [
                                for (final key in _report.columns) _label(key),
                              ],
                              exportFileName: 'yusra-${_report.view}.csv',
                              rows: [
                                for (final row in _rows)
                                  DataTablePlusRow(
                                    cells: [
                                      for (final key in _report.columns)
                                        _cell(key, row[key]),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
