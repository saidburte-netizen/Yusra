import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
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
import '../inventory/widgets/responsive_ui.dart';

class ReportDef {
  const ReportDef({
    required this.title,
    required this.view,
    required this.columns,
    required this.chartLabel,
    required this.chartValue,
    this.dateKey,
  });

  final String title;
  final String view;
  final List<String> columns;

  /// Column used for the chart's x-axis labels.
  final String chartLabel;

  /// Numeric column used for the chart's bars.
  final String chartValue;
  final String? dateKey;
}

/// Each report reads a dedicated Supabase view. Views are the single source of
/// truth for aggregation so the app never recomputes financial figures in Dart.
const List<ReportDef> _reports = [
  ReportDef(
    title: S.salesByDay,
    view: 'v_report_sales_by_day',
    columns: ['date', 'invoices', 'gross', 'discounts', 'vat', 'net'],
    chartLabel: 'date',
    chartValue: 'net',
    dateKey: 'date',
  ),
  ReportDef(
    title: S.salesByCashier,
    view: 'v_report_sales_by_cashier',
    columns: ['cashier', 'invoices', 'total'],
    chartLabel: 'cashier',
    chartValue: 'total',
  ),
  ReportDef(
    title: S.salesByPaymentMethod,
    view: 'v_report_sales_payment',
    columns: ['payment_method', 'invoices', 'total'],
    chartLabel: 'payment_method',
    chartValue: 'total',
  ),
  ReportDef(
    title: S.salesByMedicine,
    view: 'v_report_sales_by_medicine',
    columns: ['medicine', 'qty', 'revenue', 'cost', 'profit'],
    chartLabel: 'medicine',
    chartValue: 'revenue',
  ),
  ReportDef(
    title: S.profitReport,
    view: 'v_report_profit',
    columns: ['date', 'revenue', 'cost', 'profit', 'margin'],
    chartLabel: 'date',
    chartValue: 'profit',
    dateKey: 'date',
  ),
  ReportDef(
    title: S.stockValuation,
    view: 'v_report_stock_valuation',
    columns: ['medicine', 'qty', 'unit_cost', 'value'],
    chartLabel: 'medicine',
    chartValue: 'value',
  ),
  ReportDef(
    title: S.expiryLosses,
    view: 'v_report_expiry_losses',
    columns: ['expiry', 'medicine', 'batch', 'qty', 'value'],
    chartLabel: 'medicine',
    chartValue: 'value',
    dateKey: 'expiry',
  ),
  ReportDef(
    title: S.purchasesBySupplier,
    view: 'v_report_purchases_supplier',
    columns: ['supplier', 'orders', 'total'],
    chartLabel: 'supplier',
    chartValue: 'total',
  ),
  ReportDef(
    title: S.expensesReport,
    view: 'v_report_expenses',
    columns: ['date', 'category', 'amount'],
    chartLabel: 'category',
    chartValue: 'amount',
    dateKey: 'date',
  ),
  ReportDef(
    title: S.netProfit,
    view: 'v_report_net_profit',
    columns: ['period', 'revenue', 'expenses', 'net'],
    chartLabel: 'period',
    chartValue: 'net',
  ),
  ReportDef(
    title: S.shiftVariance,
    view: 'v_report_shift_variance',
    columns: ['cashier', 'shift', 'expected', 'actual', 'variance'],
    chartLabel: 'cashier',
    chartValue: 'variance',
  ),
  ReportDef(
    title: S.controlledRegister,
    view: 'v_report_controlled_register',
    columns: ['date', 'medicine', 'qty', 'prescriber', 'patient'],
    chartLabel: 'medicine',
    chartValue: 'qty',
    dateKey: 'date',
  ),
];

const Set<String> _moneyKeys = {
  'gross',
  'discounts',
  'vat',
  'net',
  'total',
  'revenue',
  'cost',
  'profit',
  'margin',
  'unit_cost',
  'value',
  'amount',
  'expenses',
  'expected',
  'actual',
  'variance',
};

/// The reports are backed by views that are not part of the base schema.
const String _viewsHint = 'If the report views are missing, apply '
    'supabase/migrations/0014_report_views.sql in the Supabase SQL Editor and '
    'try again.';

/// An older copy of 0014 does not expose branch_id; re-running the file fixes
/// the super-admin branch filter without touching any live table.
const String _branchHint =
    'If the branch filter reports a missing column, re-run '
    '0014_report_views.sql to add branch_id to the report views.';

/// Reports read database views directly. Keeping the loader behind a provider
/// lets widget tests supply dummy rows without a Supabase client while the app
/// still uses the views as the single source of truth.
typedef ReportRowsLoader = Future<List<Map<String, dynamic>>> Function(
  ReportDef report,
  String? branchId,
  DateTime? from,
  DateTime? to,
);

final reportRowsProvider = Provider<ReportRowsLoader>((ref) {
  return (report, branchId, from, to) async {
    if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
    var query = SupabaseService.client.from(report.view).select();
    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (report.dateKey != null) {
      if (from != null) {
        query = query.gte(
            report.dateKey!, startOfAddisDayUtc(from).toIso8601String());
      }
      if (to != null) {
        query =
            query.lte(report.dateKey!, endOfAddisDayUtc(to).toIso8601String());
      }
    }
    final result = await query.limit(1000);
    return List<Map<String, dynamic>>.from(result as List);
  };
});

class _Brand {
  const _Brand({
    required this.name,
    required this.tagline,
    required this.address,
    required this.phone,
    required this.tin,
    required this.licenseNo,
    required this.footer,
  });

  factory _Brand.fallback() => const _Brand(
        name: S.appName,
        tagline: S.tagline,
        address: '',
        phone: '',
        tin: '',
        licenseNo: '',
        footer: 'Thank you for choosing Yusra Pharmacy.',
      );

  final String name;
  final String tagline;
  final String address;
  final String phone;
  final String tin;
  final String licenseNo;
  final String footer;
}

class _ChartPoint {
  const _ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

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
  String? _branchId;
  List<Map<String, String>> _branches = const [];

  ReportDef get _report => _reports[_selected];

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _load();
  }

  Future<void> _loadBranches() async {
    final role = ref.read(authProvider).profile?.role;
    if (role != AppRole.superAdmin || !SupabaseService.isReady) return;
    try {
      final rows = await SupabaseService.client
          .from('branches')
          .select('id, name')
          .eq('is_active', true)
          .order('name') as List;
      if (!mounted) return;
      setState(() {
        _branches = [
          for (final row in rows)
            {
              'id': (row as Map)['id'].toString(),
              'name': (row['name'] as String?) ?? S.branch,
            },
        ];
      });
    } catch (_) {
      // The report still works across all branches; only the picker is lost.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(reportRowsProvider)
          .call(_report, _branchId, _from, _to);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = AppErrorMapper.from(e).message;
      final hint = message.toLowerCase().contains('branch_id')
          ? _branchHint
          : _viewsHint;
      setState(() {
        _error = '$message\n\n$hint';
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

  /// The chart is drawn from the rows the view already returned: no extra
  /// query and no duplicate aggregation on the device.
  List<_ChartPoint> _chartPoints() {
    final points = <_ChartPoint>[];
    for (final row in _rows) {
      final raw = row[_report.chartValue];
      final value =
          raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
      if (value == null) continue;
      points.add(_ChartPoint(
        row[_report.chartLabel]?.toString() ?? '—',
        value,
      ));
    }
    points.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return points.take(8).toList().reversed.toList();
  }

  Future<_Brand> _loadBrand() async {
    if (!SupabaseService.isReady) return _Brand.fallback();
    const keys = [
      'pharmacy_name',
      'tagline',
      'address',
      'phone',
      'tin',
      'license_no',
      'receipt_footer',
    ];
    try {
      final rows = await SupabaseService.client
          .from('app_settings')
          .select('key, value')
          .or(keys.map((key) => 'key.eq.$key').join(',')) as List;
      final values = <String, dynamic>{};
      for (final row in rows) {
        final map = row as Map;
        values[map['key'] as String] = map['value'];
      }
      String text(String key, [String fallback = '']) {
        final raw = values[key];
        if (raw is String) return raw;
        if (raw is Map) return (raw['_'] ?? raw['value'] ?? '').toString();
        return fallback;
      }

      return _Brand(
        name: text('pharmacy_name', S.appName),
        tagline: text('tagline', S.tagline),
        address: text('address'),
        phone: text('phone'),
        tin: text('tin'),
        licenseNo: text('license_no'),
        footer:
            text('receipt_footer', 'Thank you for choosing Yusra Pharmacy.'),
      );
    } catch (_) {
      return _Brand.fallback();
    }
  }

  Future<void> _exportPdf() async {
    try {
      final brand = await _loadBrand();
      final document = pw.Document();
      final tableRows = _csvRows();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(brand.name,
                    style: pw.TextStyle(
                        fontSize: 20, color: PdfColor.fromHex('#A0457A'))),
                pw.Text(brand.tagline, style: const pw.TextStyle(fontSize: 9)),
                pw.Divider(color: PdfColor.fromHex('#A8841F')),
                if (brand.address.isNotEmpty)
                  pw.Text('${S.address}: ${brand.address}',
                      style: const pw.TextStyle(fontSize: 8)),
                if (brand.phone.isNotEmpty)
                  pw.Text('${S.phone}: ${brand.phone}',
                      style: const pw.TextStyle(fontSize: 8)),
                if (brand.tin.isNotEmpty)
                  pw.Text('${S.tin}: ${brand.tin}',
                      style: const pw.TextStyle(fontSize: 8)),
                if (brand.licenseNo.isNotEmpty)
                  pw.Text('${S.licenseNo}: ${brand.licenseNo}',
                      style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Header(
              level: 0,
              child: pw.Text(_report.title),
            ),
            pw.Text(
              '${S.period}: ${_from == null ? S.all : formatDate(_from!)} — '
              '${_to == null ? S.all : formatDate(_to!)}'
              '${_branchId == null ? '' : '   •   ${S.branch}: ${_branches.where((b) => b['id'] == _branchId).map((b) => b['name']).join()}'}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: tableRows.first.map((cell) => cell as String).toList(),
              data: tableRows.skip(1).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.pink50),
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: const pw.TextStyle(fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 16),
            pw.Text(brand.footer,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
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

  /// Phones get a horizontal chip strip; larger screens keep the vertical
  /// report list. The same index drives both so selection stays in sync.
  Widget _reportPicker({required bool horizontal}) {
    if (horizontal) {
      return SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _reports.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => ChoiceChip(
            label: Text(_reports[index].title),
            selected: index == _selected,
            onSelected: (_) => _select(index),
          ),
        ),
      );
    }
    return Card(
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
                : (Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkElevated
                    : AppColors.pink50),
            child: Text('${index + 1}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: index == _selected
                        ? Colors.white
                        : (Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkPink
                            : AppColors.pink600))),
          ),
          title: Text(_reports[index].title),
          onTap: () => _select(index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    if (!can(role, Modules.reports, PermAction.view)) {
      return const Scaffold(body: Center(child: Text(S.forbiddenBody)));
    }

    return Scaffold(
      body: Padding(
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.reports,
              subtitle: _report.title,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: _rows.isEmpty ? 'No data to export.' : S.exportPdf,
                    child: OutlinedButton.icon(
                      onPressed: _rows.isEmpty ? null : _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text(S.exportPdf),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 600;
                  final dateWidth = stacked ? constraints.maxWidth : 170.0;
                  final branchWidth = stacked ? constraints.maxWidth : 190.0;
                  final content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_report.dateKey != null) ...[
                            SizedBox(
                              width: dateWidth,
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
                              width: dateWidth,
                              child: DatePickerField(
                                label: S.dateTo,
                                value: _to,
                                onChanged: (value) {
                                  setState(() => _to = value);
                                  _load();
                                },
                              ),
                            ),
                          ],
                          if (role == AppRole.superAdmin &&
                              _branches.isNotEmpty)
                            SizedBox(
                              width: branchWidth,
                              child: AppDropdown<String?>(
                                label: S.branch,
                                hint: S.allBranches,
                                value: _branchId,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(S.allBranches),
                                  ),
                                  for (final branch in _branches)
                                    DropdownMenuItem<String?>(
                                      value: branch['id'],
                                      child: Text(branch['name'] ?? S.branch),
                                    ),
                                ],
                                onChanged: (value) {
                                  setState(() => _branchId = value);
                                  _load();
                                },
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _from = null;
                                _to = null;
                                _branchId = null;
                              });
                              _load();
                            },
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text(S.reset),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Expanded(
                            child: Center(child: CircularProgressIndicator()))
                      else if (_error != null)
                        Expanded(
                            child:
                                ErrorState(message: _error!, onRetry: _retry))
                      else if (_rows.isEmpty)
                        const Expanded(
                          child: EmptyState(
                            message: 'No data for the selected period. '
                                'PDF export is unavailable until rows load.',
                            icon: Icons.insights_outlined,
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 220,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(S.chart,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  Expanded(
                                    child: _ReportChart(
                                      points: _chartPoints(),
                                      money: _moneyKeys
                                          .contains(_report.chartValue),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ResponsiveDataTablePlus(
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
                    ],
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _reportPicker(horizontal: true),
                        const SizedBox(height: 12),
                        Expanded(child: content),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 240,
                        child: _reportPicker(horizontal: false),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.points, required this.money});

  final List<_ChartPoint> points;
  final bool money;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text(S.noData));
    }
    var maxValue = 0.0;
    var minValue = 0.0;
    for (final point in points) {
      if (point.value > maxValue) maxValue = point.value;
      if (point.value < minValue) minValue = point.value;
    }
    final span = math.max(maxValue, -minValue);

    return BarChart(
      BarChartData(
        minY: minValue < 0 ? minValue * 1.15 : 0,
        maxY: span <= 0 ? 1 : maxValue * 1.15,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              '${points[groupIndex].label}\n'
              '${money ? formatMoney(rod.toY) : rod.toY.toStringAsFixed(0)}',
              const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 54,
              getTitlesWidget: (value, meta) => Text(
                _compact(value),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final label = points[index].label;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label.length > 12 ? '${label.substring(0, 12)}…' : label,
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  color: points[i].value < 0
                      ? AppColors.danger
                      : AppColors.pink600,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _compact(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(0)}k';
    return '$sign${abs.toInt()}';
  }
}
