import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/money.dart';
import '../../core/nav/menu_items.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';

class DayPoint {
  const DayPoint(this.date, this.total);

  final DateTime date;
  final double total;
}

/// Everything on this screen comes from Supabase. Each metric is loaded
/// independently so a missing optional view never blanks the whole dashboard.
class DashboardSnapshot {
  DashboardSnapshot({
    this.todaySales,
    this.monthSales,
    this.grossProfitToday,
    this.invoiceCount,
    this.openShifts,
    this.lowStock,
    this.expiringSoon,
    this.expired,
    this.pendingPrescriptions,
    this.pendingOrders,
    this.daily = const [],
    this.topMedicines = const [],
    this.recentActivity = const [],
  });

  final double? todaySales;
  final double? monthSales;
  final double? grossProfitToday;
  final int? invoiceCount;
  final int? openShifts;
  final int? lowStock;
  final int? expiringSoon;
  final int? expired;
  final int? pendingPrescriptions;
  final int? pendingOrders;
  final List<DayPoint> daily;
  final List<Map<String, dynamic>> topMedicines;
  final List<Map<String, dynamic>> recentActivity;

  static num _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static Future<List<Map<String, dynamic>>?> _rows(
      Future<dynamic> Function() query) async {
    try {
      final result = await query();
      if (result is List) {
        return List<Map<String, dynamic>>.from(result);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static double? _sum(List<Map<String, dynamic>>? rows, String key) {
    if (rows == null) return null;
    var total = 0.0;
    for (final row in rows) {
      total += _num(row[key]).toDouble();
    }
    return total;
  }

  /// Sale lines in [from]..[to] joined to medicines and their parent sale.
  /// PostgREST cannot group by, so aggregation is done in Dart.
  static Future<List<Map<String, dynamic>>?> _saleItemsBetween(
          String from, String to) =>
      _rows(() => SupabaseService.client
          .from('sale_items')
          .select('medicine_id, medicine_name, quantity, cost_price, '
              'line_total, medicines(name), sales!inner(created_at)')
          .gte('sales.created_at', from)
          .lt('sales.created_at', to));

  static bool _isExpired(Map<String, dynamic> row) {
    final value = row['is_expired'];
    return value == true || value == 'true';
  }

  static String _medicineName(Map<String, dynamic> row) {
    final embedded = row['medicines'];
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map && first['name'] != null) {
        return first['name'].toString();
      }
    } else if (embedded is Map && embedded['name'] != null) {
      return embedded['name'].toString();
    }
    return (row['medicine_name'] as String?) ?? '—';
  }

  static List<Map<String, dynamic>> _topMedicines(
      List<Map<String, dynamic>>? items) {
    if (items == null) return const [];
    final totals = <String, int>{};
    final names = <String, String>{};
    for (final row in items) {
      final id = row['medicine_id']?.toString();
      if (id == null || id.isEmpty) continue;
      totals[id] = (totals[id] ?? 0) + _num(row['quantity']).toInt();
      names.putIfAbsent(id, () => _medicineName(row));
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in ranked.take(5))
        {'name': names[entry.key] ?? '—', 'qty': entry.value},
    ];
  }

  static double? _grossProfit(List<Map<String, dynamic>>? items) {
    if (items == null) return null;
    var total = 0.0;
    for (final row in items) {
      total += _num(row['line_total']).toDouble() -
          _num(row['cost_price']).toDouble() * _num(row['quantity']).toDouble();
    }
    return total;
  }

  static Future<DashboardSnapshot> load({
    required AppRole role,
    required String? userId,
  }) async {
    if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
    final client = SupabaseService.client;
    final now = nowAddisAbaba();
    final dayStart = startOfAddisDayUtc(now).toIso8601String();
    final dayEnd = endOfAddisDayUtc(now).toIso8601String();
    final monthStart = DateTime.utc(now.year, now.month)
        .subtract(addisAbabaOffset)
        .toIso8601String();
    // Fourteen days including today (not just today repeated).
    final fortnightStart = startOfAddisDayUtc(
            now.subtract(const Duration(days: 13)))
        .toIso8601String();

    final ownOnly = isOwnOnly(role, Modules.sales);

    Future<List<Map<String, dynamic>>?> salesBetween(String from, String to) =>
        _rows(() {
          var query = client
              .from('sales')
              .select()
              .gte('created_at', from)
              .lt('created_at', to);
          if (ownOnly && userId != null) {
            query = query.eq('cashier_id', userId);
          }
          return query;
        });

    final todayRows = await salesBetween(dayStart, dayEnd);
    final monthRows = await salesBetween(monthStart, dayEnd);
    final fortnightRows = await salesBetween(fortnightStart, dayEnd);

    final dailyMap = <String, double>{};
    for (final row in fortnightRows ?? const []) {
      final stamp = row['created_at'] as String?;
      if (stamp == null) continue;
      final key = formatIsoDate(DateTime.parse(stamp));
      dailyMap[key] = (dailyMap[key] ?? 0) + _num(row['total']).toDouble();
    }
    final daily = dailyMap.entries
        .map((entry) => DayPoint(DateTime.parse(entry.key), entry.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final lowStock = await _rows(() => client.from('v_low_stock').select());
    // v_expiring_batches includes both expired and not-yet-expired batches;
    // split it with its real `is_expired` flag.
    final expiring = await _rows(() => client.from('v_expiring_batches').select());
    final shifts = await _rows(() =>
        client.from('shifts').select().eq('status', 'open'));
    final prescriptions = await _rows(() => client
        .from('prescriptions')
        .select()
        .eq('status', 'pending'));
    // po_status has no 'pending'/'approved' values: ordered and partially
    // received are the states that still need receiving.
    final orders = await _rows(() => client
        .from('purchase_orders')
        .select()
        .inFilter('status', const ['ordered', 'partially_received']));

    // Profit and top medicines come from sale_items joined to medicines;
    // sales has no `profit` column and v_top_medicines does not exist.
    final todayItems = await _saleItemsBetween(dayStart, dayEnd);
    final fortnightItems = await _saleItemsBetween(fortnightStart, dayEnd);
    final activity = await _rows(() => client
        .from('audit_logs')
        .select('id, user_id, action, table_name, old_data, new_data, created_at')
        .order('created_at', ascending: false)
        .limit(5));

    return DashboardSnapshot(
      todaySales: _sum(todayRows, 'total'),
      monthSales: _sum(monthRows, 'total'),
      grossProfitToday: _grossProfit(todayItems),
      invoiceCount: todayRows?.length,
      openShifts: shifts?.length,
      lowStock: lowStock?.length,
      expiringSoon: expiring?.where((row) => !_isExpired(row)).length,
      expired: expiring?.where(_isExpired).length,
      pendingPrescriptions: prescriptions?.length,
      pendingOrders: orders?.length,
      daily: daily,
      topMedicines: _topMedicines(fortnightItems),
      recentActivity: activity ?? const [],
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardSnapshot? _data;
  String? _error;
  bool _loading = true;

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
    final auth = ref.read(authProvider);
    try {
      final data = await DashboardSnapshot.load(
        role: auth.profile?.role ?? AppRole.cashier,
        userId: auth.profile?.id,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  String _moneyOrDash(double? value) =>
      value == null ? '—' : formatMoneyWhole(value);

  String _countOrDash(int? value) => value == null ? '—' : '$value';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final role = auth.profile?.role ?? AppRole.cashier;
    final ownOnly = isOwnOnly(role, Modules.sales);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: ownOnly ? S.backToDashboard : S.dashboard,
              subtitle: '${formatDate(nowAddisAbaba())} · ${S.appName}',
              actions: [
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else
              Expanded(
                child: SingleChildScrollView(
                  child: _DashboardBody(
                    data: _data!,
                    role: role,
                    ownOnly: ownOnly,
                    money: _moneyOrDash,
                    count: _countOrDash,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.role,
    required this.ownOnly,
    required this.money,
    required this.count,
  });

  final DashboardSnapshot data;
  final AppRole role;
  final bool ownOnly;
  final String Function(double?) money;
  final String Function(int?) count;

  @override
  Widget build(BuildContext context) {
    final shortcuts = menuFor(role).where((item) => item.path != '/dashboard').take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          children: [
            StatCard(
              title: ownOnly ? S.mySalesToday : S.todaySales,
              value: money(data.todaySales),
              icon: Icons.today_outlined,
              color: AppColors.pink600,
              subtitle: '${count(data.invoiceCount)} ${S.invoiceCount.toLowerCase()}',
            ),
            StatCard(
              title: S.monthSales,
              value: money(data.monthSales),
              icon: Icons.calendar_month_outlined,
              color: AppColors.gold700,
            ),
            StatCard(
              title: S.grossProfitToday,
              value: money(data.grossProfitToday),
              icon: Icons.trending_up_outlined,
              color: AppColors.success,
            ),
            StatCard(
              title: S.openShifts,
              value: count(data.openShifts),
              icon: Icons.access_time_outlined,
              color: AppColors.pink700,
              onTap: can(role, Modules.shifts, PermAction.view)
                  ? () => context.go('/shifts')
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(
          children: [
            StatCard(
              title: S.lowStock,
              value: count(data.lowStock),
              icon: Icons.inventory_outlined,
              color: AppColors.warning,
              onTap: can(role, Modules.stock, PermAction.view)
                  ? () => context.go('/inventory/alerts')
                  : null,
            ),
            StatCard(
              title: S.expiringSoon,
              value: count(data.expiringSoon),
              icon: Icons.event_busy_outlined,
              color: AppColors.warning,
              onTap: can(role, Modules.stock, PermAction.view)
                  ? () => context.go('/inventory/alerts')
                  : null,
            ),
            StatCard(
              title: S.expired,
              value: count(data.expired),
              icon: Icons.delete_forever_outlined,
              color: AppColors.danger,
            ),
            StatCard(
              title: S.pendingPrescriptions,
              value: count(data.pendingPrescriptions),
              icon: Icons.description_outlined,
              color: AppColors.gold700,
              onTap: can(role, Modules.prescriptions, PermAction.view)
                  ? () => context.go('/prescriptions')
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _Panel(
              width: 520,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.last14Days,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      SizedBox(height: 200, child: _SalesChart(points: data.daily)),
                    ],
                  ),
                ),
              ),
            ),
            _Panel(
              width: 300,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.topMedicines,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (data.topMedicines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text(S.noData)),
                        )
                      else
                        ...data.topMedicines.take(5).map(
                              (row) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text((row['name'] as String?) ?? '—'),
                                trailing: Text(
                                  '${row['qty'] ?? '—'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            _Panel(
              width: 300,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.alerts,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _AlertLine(
                          label: S.purchaseOrdersToReceive,
                          value: data.pendingOrders,
                          color: AppColors.gold700,
                          onTap: can(role, Modules.purchaseOrders, PermAction.view)
                              ? () => context.go('/purchasing/orders')
                              : null),
                      _AlertLine(
                          label: S.lowStock,
                          value: data.lowStock,
                          color: AppColors.warning,
                          onTap: can(role, Modules.stock, PermAction.view)
                              ? () => context.go('/inventory/alerts')
                              : null),
                      _AlertLine(
                          label: S.expiringSoon,
                          value: data.expiringSoon,
                          color: AppColors.danger,
                          onTap: can(role, Modules.stock, PermAction.view)
                              ? () => context.go('/inventory/alerts')
                              : null),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _Panel(
              width: 420,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.recentActivity,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      if (data.recentActivity.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text(S.noData)),
                        )
                      else
                        ...data.recentActivity.take(5).map(
                              (row) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text((row['action'] as String?) ?? '—'),
                                subtitle: Text((row['table_name'] as String?) ?? ''),
                                trailing: row['created_at'] == null
                                    ? null
                                    : Text(formatDateTime(
                                        DateTime.parse(row['created_at'] as String))),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
            _Panel(
              width: 420,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.shortcuts,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in shortcuts)
                            ActionChip(
                              avatar: Icon(item.icon, size: 16),
                              label: Text(item.label),
                              onPressed: () => context.go(item.path),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AlertLine extends StatelessWidget {
  const _AlertLine({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final int? value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        foregroundColor: color,
        radius: 14,
        child: Text(value == null ? '?' : '$value',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.points});

  final List<DayPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text(S.noData));
    }
    final maxValue = points.fold<double>(
        0, (previous, point) => point.total > previous ? point.total : previous);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue <= 0 ? 100 : maxValue * 1.15,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  formatDate(points[index].date, pattern: 'dd MMM'),
                  style: Theme.of(context).textTheme.labelSmall,
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].total),
            ],
            isCurved: true,
            color: AppColors.pink600,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.pink600.withOpacity(0.22),
                  AppColors.pink600.withOpacity(0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _compact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
    return value.toInt().toString();
  }
}

/// Keeps the dashboard panels at their preferred width on desktop without
/// overflowing a phone screen.
class _Panel extends StatelessWidget {
  const _Panel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}
