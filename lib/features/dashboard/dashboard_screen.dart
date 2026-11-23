import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/activity/activity.dart';
import '../../core/activity/activity_range.dart';
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
import '../inventory/data/inventory_providers.dart';
import 'dashboard_metrics.dart';

class DayPoint {
  const DayPoint(this.date, this.total);

  final DateTime date;
  final double total;
}

/// One employee's current standing, shown to admins on the dashboard.
class TeamMemberStatus {
  const TeamMemberStatus({
    required this.id,
    required this.name,
    required this.role,
    required this.todaySales,
    required this.todayInvoices,
    required this.hasOpenShift,
    this.lastActive,
  });

  final String id;
  final String name;
  final AppRole role;
  final double todaySales;
  final int todayInvoices;
  final bool hasOpenShift;
  final DateTime? lastActive;
}

class _UserSales {
  double total = 0;
  int count = 0;
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
    this.periodSales,
    this.periodProfit,
    this.periodInvoices,
    this.daily = const [],
    this.topMedicines = const [],
    this.recentActivity = const [],
    this.recentActivityLog = const [],
    this.failedSections = const [],
    this.teamStatus = const [],
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

  /// Sales/profit/invoice count for the selected [ActivityRange].
  final double? periodSales;
  final double? periodProfit;
  final int? periodInvoices;
  final List<DayPoint> daily;
  final List<Map<String, dynamic>> topMedicines;

  /// Kept for CSV/debug parity; the UI uses the typed activity_log list.
  final List<Map<String, dynamic>> recentActivity;
  final List<ActivityEntry> recentActivityLog;

  /// Human-readable names of queries that failed; drives the partial-data banner.
  final List<String> failedSections;
  final List<TeamMemberStatus> teamStatus;

  static num _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static Future<List<Map<String, dynamic>>?> _rows(
    Future<dynamic> Function() query, {
    List<String>? failures,
    String? label,
  }) async {
    try {
      final result = await query();
      if (result is List) {
        return List<Map<String, dynamic>>.from(result);
      }
      if (label != null) {
        failures?.add('$label (Error code: UNKNOWN)');
      }
      return null;
    } catch (error) {
      // Individual cards must not take down the whole dashboard; record the
      // failed section AND its mapped code so the partial-data banner tells
      // the user what actually broke instead of a generic sentence.
      if (label != null) {
        final mapped = AppErrorMapper.from(error);
        failures?.add('$label (${mapped.codeLine ?? 'Error code: UNKNOWN'})');
      }
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
    String from,
    String to, {
    String? branchId,
    bool ownOnly = false,
    String? userId,
    List<String>? failures,
  }) =>
      _rows(() {
        // Both FKs are spelled out: `sale_items` also has a batch_id FK, so
        // letting PostgREST guess the relationship makes the embed ambiguous
        // (PGRST200/201). Filters use the `sale:` alias declared in select.
        var query = SupabaseService.client
            .from('sale_items')
            .select(
              'medicine_id, medicine_name, quantity, cost_price, line_total, '
              'medicine:medicines!sale_items_medicine_id_fkey(name), '
              'sale:sales!sale_items_sale_id_fkey!inner(created_at)',
            )
            .gte('sale.created_at', from)
            .lt('sale.created_at', to);
        if (branchId != null) query = query.eq('sale.branch_id', branchId);
        if (ownOnly && userId != null) {
          query = query.eq('sale.cashier_id', userId);
        }
        return query;
      }, failures: failures, label: 'Sales detail');

  static bool isExpiredBatch(Map<String, dynamic> row) =>
      dashboardIsExpiredBatch(row);

  static List<Map<String, dynamic>> topMedicinesFrom(
          List<Map<String, dynamic>>? items) =>
      dashboardTopMedicines(items);

  static double? grossProfitFrom(List<Map<String, dynamic>>? items) =>
      dashboardGrossProfit(items);

  static Future<DashboardSnapshot> load({
    required AppRole role,
    required String? userId,
    required ActivityRange range,
    String? branchId,
  }) async {
    if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
    final client = SupabaseService.client;
    final now = nowAddisAbaba();
    final dayStart = startOfAddisDayUtc(now).toIso8601String();
    final dayEnd = endOfAddisDayUtc(now).toIso8601String();
    final monthStart = DateTime.utc(now.year, now.month)
        .subtract(addisAbabaOffset)
        .toIso8601String();
    final rangeStart = activityRangeStart(range, now: now);
    final periodStart = (rangeStart ?? DateTime.utc(1900)).toIso8601String();
    // An unbounded range would draw thousands of chart points. Totals still
    // cover all time, but the trend line shows the most recent 90 days.
    final chartStart = (range == ActivityRange.all
            ? startOfAddisDayUtc(now.subtract(const Duration(days: 89)))
            : rangeStart!)
        .toIso8601String();

    final failures = <String>[];
    final ownOnly = isOwnOnly(role, Modules.sales);

    Future<List<Map<String, dynamic>>?> salesBetween(
      String from,
      String to, {
      required String label,
    }) =>
        _rows(() {
          var query = client
              .from('sales')
              .select()
              .gte('created_at', from)
              .lt('created_at', to);
          if (branchId != null) query = query.eq('branch_id', branchId);
          if (ownOnly && userId != null) {
            query = query.eq('cashier_id', userId);
          }
          return query;
        }, failures: failures, label: label);

    final todayRows =
        await salesBetween(dayStart, dayEnd, label: "Today's sales");
    final monthRows =
        await salesBetween(monthStart, dayEnd, label: 'Monthly sales');
    final periodRows =
        await salesBetween(periodStart, dayEnd, label: '${range.label} sales');

    final dailyMap = <String, double>{};
    for (final row in periodRows ?? const []) {
      final stamp = row['created_at'] as String?;
      if (stamp == null || stamp.compareTo(chartStart) < 0) continue;
      final key = formatIsoDate(DateTime.parse(stamp));
      dailyMap[key] = (dailyMap[key] ?? 0) + _num(row['total']).toDouble();
    }
    final daily = dailyMap.entries
        .map((entry) => DayPoint(DateTime.parse(entry.key), entry.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    Future<List<Map<String, dynamic>>?> branchRows(
      String table, {
      required String label,
      String? Function(PostgrestFilterBuilder query)? filter,
    }) async {
      return _rows(() {
        var query = client.from(table).select();
        if (branchId != null) query = query.eq('branch_id', branchId);
        filter?.call(query);
        return query;
      }, failures: failures, label: label);
    }

    final lowStock = await branchRows('v_low_stock', label: 'Low stock');
    // v_expiring_batches includes both expired and not-yet-expired batches;
    // split it with its real `is_expired` flag.
    final expiring =
        await branchRows('v_expiring_batches', label: 'Expiry alerts');
    final shifts = await _rows(() {
      var query = client.from('shifts').select().eq('status', 'open');
      if (branchId != null) query = query.eq('branch_id', branchId);
      return query;
    }, failures: failures, label: 'Open shifts');
    final prescriptions = await _rows(() {
      var query = client.from('prescriptions').select().eq('status', 'pending');
      if (branchId != null) query = query.eq('branch_id', branchId);
      return query;
    }, failures: failures, label: 'Prescriptions');
    // po_status has no 'pending'/'approved' values: ordered and partially
    // received are the states that still need receiving.
    final orders = await _rows(() {
      var query = client
          .from('purchase_orders')
          .select()
          .inFilter('status', const ['ordered', 'partially_received']);
      if (branchId != null) query = query.eq('branch_id', branchId);
      return query;
    }, failures: failures, label: 'Purchase orders');

    // Profit and top medicines come from sale_items joined to medicines;
    // sales has no `profit` column and v_top_medicines does not exist.
    final todayItems = await _saleItemsBetween(
      dayStart,
      dayEnd,
      branchId: branchId,
      ownOnly: ownOnly,
      userId: userId,
      failures: failures,
    );
    final periodItems = await _saleItemsBetween(
      periodStart,
      dayEnd,
      branchId: branchId,
      ownOnly: ownOnly,
      userId: userId,
      failures: failures,
    );

    // One unified activity stream (activity_log) feeds recent activity, the
    // audit trail and each employee's last-active timestamp.
    final activity = await _rows(() {
      var query = client
          .from('activity_log')
          .select('id, actor_id, actor_email, actor_role, action, entity_type, '
              'entity_id, summary, branch_id, created_at, '
              'correction_requested, correction_reason, approved_at');
      if (branchId != null) query = query.eq('branch_id', branchId);
      return query.order('created_at', ascending: false).limit(100);
    }, failures: failures, label: 'Activity log');

    // Admins see each employee's live standing, scoped to the selected branch.
    final team = <TeamMemberStatus>[];
    if (role == AppRole.superAdmin || role == AppRole.admin) {
      final people = await _rows(() {
        var query = client
            .from('profiles')
            .select('id, email, full_name, role, is_active')
            .eq('is_active', true);
        if (branchId != null) query = query.eq('branch_id', branchId);
        return query;
      }, failures: failures, label: 'Team members');
      final salesByUser = <String, _UserSales>{};
      for (final row in todayRows ?? const []) {
        final id = row['cashier_id']?.toString();
        if (id == null) continue;
        final entry = salesByUser.putIfAbsent(id, _UserSales.new);
        entry.total += _num(row['total']).toDouble();
        entry.count += 1;
      }
      final openShiftUsers = <String>{};
      for (final row in shifts ?? const []) {
        final id = row['cashier_id']?.toString();
        if (id != null) openShiftUsers.add(id);
      }
      final lastActive = <String, DateTime>{};
      for (final row in activity ?? const []) {
        final id = row['actor_id']?.toString();
        final parsed = DateTime.tryParse(row['created_at']?.toString() ?? '');
        if (id == null || parsed == null) continue;
        final previous = lastActive[id];
        if (previous == null || parsed.isAfter(previous)) {
          lastActive[id] = parsed;
        }
      }
      for (final person in people ?? const []) {
        final id = person['id']?.toString();
        if (id == null) continue;
        final name = (person['full_name'] as String?)?.trim() ?? '';
        final sales = salesByUser[id];
        team.add(TeamMemberStatus(
          id: id,
          name: name.isEmpty ? (person['email'] as String? ?? '—') : name,
          role: AppRoleX.fromDb(person['role'] as String?) ?? AppRole.cashier,
          todaySales: sales?.total ?? 0,
          todayInvoices: sales?.count ?? 0,
          hasOpenShift: openShiftUsers.contains(id),
          lastActive:
              lastActive[id] == null ? null : toAddisAbaba(lastActive[id]!),
        ));
      }
      team.sort((a, b) => b.todaySales.compareTo(a.todaySales));
    }

    return DashboardSnapshot(
      todaySales: _sum(todayRows, 'total'),
      monthSales: _sum(monthRows, 'total'),
      grossProfitToday: grossProfitFrom(todayItems),
      invoiceCount: todayRows?.length,
      openShifts: shifts?.length,
      lowStock: lowStock?.length,
      expiringSoon: expiring?.where((row) => !isExpiredBatch(row)).length,
      expired: expiring?.where(isExpiredBatch).length,
      pendingPrescriptions: prescriptions?.length,
      pendingOrders: orders?.length,
      periodSales: _sum(periodRows, 'total'),
      periodProfit: grossProfitFrom(periodItems),
      periodInvoices: periodRows?.length,
      daily: daily,
      topMedicines: topMedicinesFrom(periodItems),
      recentActivity: activity ?? const [],
      recentActivityLog: [
        for (final row in activity ?? const []) ActivityEntry.fromJson(row),
      ],
      failedSections: failures.toSet().toList(),
      teamStatus: team,
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    this.initialSnapshot,
    this.initialError,
  });

  /// Optional test seam: widget tests inject dummy data instead of Supabase.
  /// Production navigation uses the plain constructor and loads normally.
  final DashboardSnapshot? initialSnapshot;
  final String? initialError;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardSnapshot? _data;
  String? _error;
  bool _loading = true;
  RealtimeChannel? _channel;
  ActivityRange _range = ActivityRange.today;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _branchId = ref.read(branchScopeProvider);
    if (widget.initialSnapshot != null || widget.initialError != null) {
      _data = widget.initialSnapshot;
      _error = widget.initialError;
      _loading = false;
    } else {
      _load();
    }
    _subscribeToChanges();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null && SupabaseService.isReady) {
      SupabaseService.client.removeChannel(channel);
    }
    super.dispose();
  }

  /// Counters must stay live while the screen is open: a sale or a stock
  /// movement written by another device has to move the numbers without the
  /// user pressing refresh.
  void _subscribeToChanges() {
    if (!SupabaseService.isReady) return;
    _channel = SupabaseService.client
        .channel('dashboard-counters')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stock_batches',
          callback: (_) => _refreshQuiet(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sales',
          callback: (_) => _refreshQuiet(),
        )..subscribe();
  }

  /// Realtime events can arrive in bursts. Reload without flipping into the
  /// loading state so the dashboard never flickers or loses its last snapshot.
  Future<void> _refreshQuiet() async {
    final auth = ref.read(authProvider);
    try {
      final data = await DashboardSnapshot.load(
        role: auth.profile?.role ?? AppRole.cashier,
        userId: auth.profile?.id,
        range: _range,
        branchId: _branchId,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      // Keep the last good snapshot; the manual refresh still surfaces errors.
    }
  }

  /// Friendly message plus a copyable code line, even for unmapped errors.
  static String _errorText(Object error) {
    final mapped = AppErrorMapper.from(error);
    final codeLine = mapped.codeLine;
    if (codeLine != null) {
      return mapped.message.contains(codeLine)
          ? mapped.message
          : '${mapped.message}\n$codeLine';
    }
    return '${mapped.message}\nError code: UNKNOWN';
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
        range: _range,
        branchId: _branchId,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(e);
        _loading = false;
      });
    }
  }

  String _moneyOrDash(double? value) =>
      value == null ? '—' : formatMoneyWhole(value);

  String _countOrDash(int? value) => value == null ? '—' : '$value';

  String _greeting() {
    final hour = nowAddisAbaba().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    ref.listen<String?>(branchScopeProvider, (previous, next) {
      if (previous != next) {
        _branchId = next;
        _load();
      }
    });
    final role = auth.profile?.role ?? AppRole.cashier;
    final ownOnly = isOwnOnly(role, Modules.sales);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final rangeWidth = screenWidth < 600 ? screenWidth - 40 : 190.0;
    final name = auth.profile?.fullName.trim();
    final greetingName = (name == null || name.isEmpty) ? '' : ', $name';

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin:
                  EdgeInsets.fromLTRB(16, screenWidth < 600 ? 12 : 20, 16, 0),
              padding: EdgeInsets.all(screenWidth < 600 ? 12 : 24),
              decoration: BoxDecoration(
                gradient: AppColors.darkGradient,
                borderRadius:
                    BorderRadius.circular(screenWidth < 600 ? 16 : 22),
                border: Border.all(color: AppColors.gold500.withOpacity(0.35)),
                boxShadow: const [AppColors.cardShadow],
              ),
              child: screenWidth < 600
                  ? Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_greeting()}$greetingName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: AppColors.onDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatDate(nowAddisAbaba()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.onDarkMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const ThemeModeToggle(iconOnly: true),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 118,
                          child: DropdownButtonFormField<ActivityRange>(
                            value: _range,
                            isExpanded: true,
                            dropdownColor: AppColors.plum900,
                            style: const TextStyle(
                              color: AppColors.onDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            iconEnabledColor: AppColors.gold300,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              filled: true,
                              fillColor: AppColors.plum900.withOpacity(0.35),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: Color(0x59C9A227)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: AppColors.gold500),
                              ),
                            ),
                            items: [
                              for (final r in ActivityRange.values)
                                DropdownMenuItem(
                                  value: r,
                                  child: Text(r.label,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) {
                              setState(() => _range = v ?? ActivityRange.all);
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: _load,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                AppColors.gold500.withOpacity(0.18),
                            foregroundColor: AppColors.gold300,
                          ),
                          icon: const Icon(Icons.refresh, size: 20),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_greeting()}$greetingName',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: AppColors.onDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${formatDate(nowAddisAbaba())} · ${S.appName}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppColors.onDarkMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const SizedBox(
                              width: 240,
                              child: ThemeModeToggle(compact: true),
                            ),
                            SizedBox(
                              width: rangeWidth,
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  inputDecorationTheme: Theme.of(context)
                                      .inputDecorationTheme
                                      .copyWith(
                                        fillColor:
                                            AppColors.plum900.withOpacity(0.35),
                                        labelStyle: const TextStyle(
                                          color: AppColors.onDarkMuted,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                ),
                                child: DropdownButtonFormField<ActivityRange>(
                                  value: _range,
                                  isExpanded: true,
                                  dropdownColor: AppColors.plum900,
                                  style: const TextStyle(
                                    color: AppColors.onDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  iconEnabledColor: AppColors.gold300,
                                  decoration: const InputDecoration(
                                    labelText: S.timeRange,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(14)),
                                      borderSide:
                                          BorderSide(color: Color(0x59C9A227)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(14)),
                                      borderSide:
                                          BorderSide(color: AppColors.gold500),
                                    ),
                                  ),
                                  items: [
                                    for (final r in ActivityRange.values)
                                      DropdownMenuItem(
                                        value: r,
                                        child: Text(r.label),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    setState(
                                        () => _range = v ?? ActivityRange.all);
                                    _load();
                                  },
                                ),
                              ),
                            ),
                            IconButton.filled(
                              onPressed: _load,
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    AppColors.gold500.withOpacity(0.18),
                                foregroundColor: AppColors.gold300,
                              ),
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(screenWidth < 600 ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_loading &&
                      _error == null &&
                      _data?.failedSections.isNotEmpty == true)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: AppColors.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                    'Some sections could not be loaded:'),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _data!.failedSections
                                      .map((section) => '• $section')
                                      .join('\n'),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                    'The numbers shown may be incomplete.'),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text(S.retry),
                          ),
                        ],
                      ),
                    ),
                  if (_loading && _data == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _data == null)
                    ErrorState(message: _error!, onRetry: _load)
                  else if (_data != null) ...[
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    _DashboardBody(
                      data: _data!,
                      role: role,
                      ownOnly: ownOnly,
                      money: _moneyOrDash,
                      count: _countOrDash,
                      range: _range,
                    ),
                  ],
                ],
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
    required this.range,
  });

  final DashboardSnapshot data;
  final AppRole role;
  final bool ownOnly;
  final String Function(double?) money;
  final String Function(int?) count;
  final ActivityRange range;

  @override
  Widget build(BuildContext context) {
    final shortcuts = menuFor(role)
        .where((item) => item.path != '/dashboard')
        .take(4)
        .toList();
    final showFinance = can(role, Modules.reports, PermAction.view);
    final showStaff = role == AppRole.superAdmin || role == AppRole.admin;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final gridMin = narrow ? 150.0 : 260.0;
    final gridSpacing = narrow ? 10.0 : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveGrid(
          minTileWidth: gridMin,
          spacing: gridSpacing,
          children: [
            StatCard(
              compact: narrow,
              title: ownOnly ? S.mySalesToday : S.todaySales,
              value: money(data.todaySales),
              icon: Icons.today_outlined,
              color: AppColors.pink600,
              subtitle:
                  '${count(data.invoiceCount)} ${S.invoiceCount.toLowerCase()}',
            ),
            if (showFinance)
              StatCard(
                compact: narrow,
                title: S.monthSales,
                value: money(data.monthSales),
                icon: Icons.calendar_month_outlined,
                color: AppColors.gold700,
              ),
            if (showFinance)
              StatCard(
                compact: narrow,
                title: S.grossProfitToday,
                value: money(data.grossProfitToday),
                icon: Icons.trending_up_outlined,
                color: AppColors.success,
              ),
            StatCard(
              compact: narrow,
              title: S.openShifts,
              value: count(data.openShifts),
              icon: Icons.access_time_outlined,
              color: AppColors.pink700,
              onTap: can(role, Modules.shifts, PermAction.view)
                  ? () => context.go('/shifts')
                  : null,
            ),
            if (showStaff)
              StatCard(
                compact: narrow,
                title: 'Staff count',
                value: '${data.teamStatus.length}',
                icon: Icons.groups_outlined,
                color: AppColors.plum600,
                onTap: () => context.go('/admin/users'),
              ),
            if (showStaff)
              StatCard(
                compact: narrow,
                title: 'On shift',
                value: '${data.teamStatus.where((m) => m.hasOpenShift).length}',
                icon: Icons.badge_outlined,
                color: AppColors.success,
                onTap: () => context.go('/admin/users'),
              ),
          ],
        ),
        SizedBox(height: narrow ? 10 : 16),
        ResponsiveGrid(
          minTileWidth: gridMin,
          spacing: gridSpacing,
          children: [
            StatCard(
              compact: narrow,
              title: S.lowStock,
              value: count(data.lowStock),
              icon: Icons.inventory_outlined,
              color: AppColors.warning,
              onTap: can(role, Modules.stock, PermAction.view)
                  ? () => context.go('/inventory/alerts')
                  : null,
            ),
            StatCard(
              compact: narrow,
              title: S.expiringSoon,
              value: count(data.expiringSoon),
              icon: Icons.event_busy_outlined,
              color: AppColors.warning,
              onTap: can(role, Modules.stock, PermAction.view)
                  ? () => context.go('/inventory/alerts')
                  : null,
            ),
            StatCard(
              compact: narrow,
              title: S.expired,
              value: count(data.expired),
              icon: Icons.delete_forever_outlined,
              color: AppColors.danger,
            ),
            StatCard(
              compact: narrow,
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
                      Text('${S.salesByDay} · ${range.label}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      SizedBox(
                          height: 200, child: _SalesChart(points: data.daily)),
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
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
                          onTap:
                              can(role, Modules.purchaseOrders, PermAction.view)
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
              width: 520,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${S.activity} · ${range.label}',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (can(role, Modules.audit, PermAction.view))
                            TextButton(
                              onPressed: () => context.go('/admin/audit'),
                              child: const Text(S.view),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (data.recentActivityLog.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text(S.noActivity)),
                        )
                      else
                        ...data.recentActivityLog.take(6).map(
                              (entry) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(entry.displayAction),
                                subtitle:
                                    Text('${entry.email} · ${entry.role}'),
                                trailing: Text(
                                    formatDateTime(entry.createdAt.toUtc())),
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
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in shortcuts)
                            InkWell(
                              onTap: () => context.go(item.path),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: 120,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.gold300.withOpacity(0.55),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0F4A1230),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? AppColors.darkElevated
                                            : AppColors.pink50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        item.icon,
                                        size: 20,
                                        color: AppColors.plum800,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      item.label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.plum800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (role == AppRole.superAdmin || role == AppRole.admin)
              _Panel(
                width: 520,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Icon(Icons.groups_outlined,
                                size: 20, color: AppColors.pink700),
                            Text(S.teamActivity,
                                style: Theme.of(context).textTheme.titleMedium),
                            TextButton.icon(
                              onPressed: () => context.go('/admin/users'),
                              icon: const Icon(Icons.manage_accounts_outlined,
                                  size: 18),
                              label: const Text(S.users),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (data.teamStatus.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: Text(S.noTeamMembers)),
                          )
                        else
                          ...data.teamStatus.map(
                            (member) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: Text(member.name.isEmpty
                                    ? '?'
                                    : member.name
                                        .substring(0, 1)
                                        .toUpperCase()),
                              ),
                              title: Text(member.name),
                              subtitle: Text(
                                [
                                  member.role.label,
                                  money(member.todaySales),
                                  '${member.todayInvoices} ${S.invoiceCount.toLowerCase()}',
                                  member.hasOpenShift ? S.shiftOpen : S.noShift,
                                  if (member.lastActive != null)
                                    '${S.lastActive}: ${formatDateTime(member.lastActive!)}',
                                ].join(' · '),
                              ),
                            ),
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
    final maxValue = points.fold<double>(0,
        (previous, point) => point.total > previous ? point.total : previous);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxValue <= 0 ? 100 : maxValue * 1.15,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
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
