// Repository for the twelve report views used by the Reports screen.
//
// The views own all aggregation; this class only builds the same branch/date
// filtered reads the screen does, so the e2e suite can exercise them through
// real PostgREST requests instead of replaying SQL.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/dates.dart';
import '../../../core/supabase_client.dart';

class ReportDefinition {
  const ReportDefinition({
    required this.key,
    required this.view,
    this.dateKey,
  });

  final String key;
  final String view;
  final String? dateKey;
}

/// The twelve reports in the order shown in the app.
const List<ReportDefinition> reportDefinitions = [
  ReportDefinition(
      key: 'salesByDay', view: 'v_report_sales_by_day', dateKey: 'date'),
  ReportDefinition(key: 'salesByCashier', view: 'v_report_sales_by_cashier'),
  ReportDefinition(key: 'salesByPayment', view: 'v_report_sales_payment'),
  ReportDefinition(key: 'salesByMedicine', view: 'v_report_sales_by_medicine'),
  ReportDefinition(key: 'profit', view: 'v_report_profit', dateKey: 'date'),
  ReportDefinition(key: 'stockValuation', view: 'v_report_stock_valuation'),
  ReportDefinition(
      key: 'expiryLosses', view: 'v_report_expiry_losses', dateKey: 'expiry'),
  ReportDefinition(
      key: 'purchasesSupplier', view: 'v_report_purchases_supplier'),
  ReportDefinition(key: 'expenses', view: 'v_report_expenses', dateKey: 'date'),
  ReportDefinition(key: 'netProfit', view: 'v_report_net_profit'),
  ReportDefinition(key: 'shiftVariance', view: 'v_report_shift_variance'),
  ReportDefinition(
      key: 'controlledRegister',
      view: 'v_report_controlled_register',
      dateKey: 'date'),
];

class ReportsRepository {
  SupabaseClient get _db => SupabaseService.client;

  /// One report view, with the same filters/limit the Reports screen applies.
  Future<List<Map<String, dynamic>>> rows(
    ReportDefinition report, {
    String? branchId,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _db.from(report.view).select();
    if (branchId != null) query = query.eq('branch_id', branchId);
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
    final result = await query.limit(1000) as List;
    return result
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  /// All twelve views in one call, keyed by [ReportDefinition.key].
  Future<Map<String, List<Map<String, dynamic>>>> allForBranch(
    String branchId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final report in reportDefinitions) {
      result[report.key] =
          await rows(report, branchId: branchId, from: from, to: to);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> salesByDay(
          {String? branchId, DateTime? from, DateTime? to}) =>
      rows(reportDefinitions[0], branchId: branchId, from: from, to: to);

  Future<List<Map<String, dynamic>>> salesByCashier({String? branchId}) =>
      rows(reportDefinitions[1], branchId: branchId);

  Future<List<Map<String, dynamic>>> salesByPayment({String? branchId}) =>
      rows(reportDefinitions[2], branchId: branchId);

  Future<List<Map<String, dynamic>>> salesByMedicine({String? branchId}) =>
      rows(reportDefinitions[3], branchId: branchId);

  Future<List<Map<String, dynamic>>> profit(
          {String? branchId, DateTime? from, DateTime? to}) =>
      rows(reportDefinitions[4], branchId: branchId, from: from, to: to);

  Future<List<Map<String, dynamic>>> stockValuation({String? branchId}) =>
      rows(reportDefinitions[5], branchId: branchId);

  Future<List<Map<String, dynamic>>> expiryLosses(
          {String? branchId, DateTime? from, DateTime? to}) =>
      rows(reportDefinitions[6], branchId: branchId, from: from, to: to);

  Future<List<Map<String, dynamic>>> purchasesSupplier({String? branchId}) =>
      rows(reportDefinitions[7], branchId: branchId);

  Future<List<Map<String, dynamic>>> expenses(
          {String? branchId, DateTime? from, DateTime? to}) =>
      rows(reportDefinitions[8], branchId: branchId, from: from, to: to);

  Future<List<Map<String, dynamic>>> netProfit({String? branchId}) =>
      rows(reportDefinitions[9], branchId: branchId);

  Future<List<Map<String, dynamic>>> shiftVariance({String? branchId}) =>
      rows(reportDefinitions[10], branchId: branchId);

  Future<List<Map<String, dynamic>>> controlledRegister(
          {String? branchId, DateTime? from, DateTime? to}) =>
      rows(reportDefinitions[11], branchId: branchId, from: from, to: to);
}
