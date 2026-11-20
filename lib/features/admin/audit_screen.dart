import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity/activity.dart';
import '../../core/activity/activity_range.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/widgets.dart';

/// Read-only, append-only activity trail backed by `activity_log`.
/// Writes are made by database triggers with the signed-in user's email,
/// role and Addis timestamp. Nothing here can be edited or deleted directly;
/// corrections require a super-admin approval.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  ActivityRange _range = ActivityRange.today;
  bool _busy = false;

  Future<void> _act(ActivityEntry entry, {required bool approve}) async {
    setState(() => _busy = true);
    try {
      final ok = approve
          ? await approveActivityCorrection(entry.id)
          : await requestActivityCorrection(entry.id, S.requestCorrection);
      if (!mounted) return;
      ref.invalidate(activityProvider);
      AppSnackbar.success(context, ok ? S.saved : S.somethingWrong);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role;
    final isSuper = role == AppRole.superAdmin;
    final async = ref.watch(activityProvider);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.audit,
              subtitle: S.auditNote,
              actions: [
                SizedBox(
                  width: 190,
                  child: AppDropdown<ActivityRange>(
                    label: S.timeRange,
                    value: _range,
                    items: [
                      for (final r in ActivityRange.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _range = v ?? ActivityRange.all),
                  ),
                ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () => ref.invalidate(activityProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(activityProvider),
                ),
                data: (entries) {
                  final shown = filterActivities(entries, _range);
                  return DataTablePlus(
                    columns: const [
                      S.dateTimeLabel,
                      S.email,
                      S.role,
                      S.actionLabel,
                      S.status,
                      S.actionLabel,
                    ],
                    exportFileName: 'yusra-activity-log.csv',
                    rows: [
                      for (final entry in shown)
                        DataTablePlusRow(
                          cells: [
                            formatDateTime(entry.createdAt.toUtc()),
                            entry.email,
                            entry.role,
                            entry.displayAction,
                            entry.correctionRequested
                                ? S.pendingApproval
                                : entry.approvedAt != null
                                    ? S.approved
                                    : '—',
                            entry.correctionReason ?? '',
                          ],
                          actions: [
                            if (!_busy && isSuper && entry.correctionRequested)
                              IconButton(
                                tooltip: S.approveCorrection,
                                icon: const Icon(Icons.verified_outlined, size: 18),
                                onPressed: () => _act(entry, approve: true),
                              ),
                            if (!_busy && !isSuper && !entry.correctionRequested)
                              IconButton(
                                tooltip: S.requestCorrection,
                                icon: const Icon(Icons.report_outlined, size: 18),
                                onPressed: () => _act(entry, approve: false),
                              ),
                          ],
                        ),
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
