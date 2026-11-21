import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import 'activity_range.dart';

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.email,
    required this.role,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.summary,
    this.branchId,
    this.correctionRequested = false,
    this.correctionReason,
    this.approvedAt,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        id: (json['id'] as String?) ?? '',
        email: (json['actor_email'] as String?) ?? 'system',
        role: (json['actor_role'] as String?) ?? 'system',
        action: (json['action'] as String?) ?? '',
        entityType: (json['entity_type'] as String?) ?? '',
        entityId: (json['entity_id'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        summary: json['summary'] as String?,
        branchId: json['branch_id'] as String?,
        correctionRequested: json['correction_requested'] as bool? ?? false,
        correctionReason: json['correction_reason'] as String?,
        approvedAt: DateTime.tryParse((json['approved_at'] as String?) ?? ''),
      );

  final String id;
  final String email;
  final String role;
  final String action;
  final String entityType;
  final String entityId;
  final DateTime createdAt;
  final String? summary;
  final String? branchId;
  final bool correctionRequested;
  final String? correctionReason;
  final DateTime? approvedAt;

  String get displayAction =>
      '${entityType.isNotEmpty ? entityType : 'record'} $action';
}

final activityProvider =
    FutureProvider.autoDispose<List<ActivityEntry>>((ref) async {
  if (!SupabaseService.isReady) {
    throw const SupabaseNotConfigured();
  }
  final client = SupabaseService.client;
  final rows = await client
      .from('activity_log')
      .select()
      .order('created_at', ascending: false)
      .limit(500);
  final entries = [
    for (final row in rows as List)
      ActivityEntry.fromJson(Map<String, dynamic>.from(row as Map)),
  ];

  // Realtime: every change to the log refreshes the dashboard immediately.
  final channel = client.channel('yusra-activity-log');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'activity_log',
        callback: (payload) => ref.invalidateSelf(),
      )
      .subscribe();
  ref.onDispose(() {
    client.removeChannel(channel);
  });

  return entries;
});

List<ActivityEntry> filterActivities(
  List<ActivityEntry> entries,
  ActivityRange range, {
  DateTime? now,
}) {
  final start = activityRangeStart(range, now: now);
  if (start == null) return entries;
  return entries
      .where((entry) => !entry.createdAt.toUtc().isBefore(start))
      .toList();
}

Future<bool> requestActivityCorrection(String id, String reason) async {
  final response = await SupabaseService.client.rpc(
      'request_activity_correction',
      params: {'p_log_id': id, 'p_reason': reason});
  return response == true;
}

Future<bool> approveActivityCorrection(String id) async {
  final response = await SupabaseService.client
      .rpc('approve_activity_correction', params: {'p_log_id': id});
  return response == true;
}
