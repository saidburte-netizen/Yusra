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

const _reasonHeader = 'Reason';
const _minReasonLength = 10;
const _reasonTooShort =
    'Enter at least 10 characters so an admin understands the correction.';

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
  // The audit is a full history by default; narrower ranges are opt-in.
  ActivityRange _range = ActivityRange.all;
  String? _statusFilter;
  bool _busy = false;

  Future<void> _approve(ActivityEntry entry) async {
    await _runRpc(
      () => approveActivityCorrection(entry.id),
      successMessage: S.approved,
    );
  }

  Future<void> _requestCorrection(ActivityEntry entry) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (reason == null || !mounted) return;
    await _runRpc(
      () => requestActivityCorrection(entry.id, reason),
      successMessage: S.pendingApproval,
    );
  }

  Future<void> _runRpc(
    Future<bool> Function() rpc, {
    required String successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      final ok = await rpc();
      if (!mounted) return;
      if (ok) {
        ref.invalidate(activityProvider);
        AppSnackbar.success(context, successMessage);
      } else {
        // The RPC returns false when the row is no longer eligible; never
        // present that as a successful save.
        AppSnackbar.error(context, S.somethingWrong);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showDetails(ActivityEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.view),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detail(S.dateTimeLabel, formatDateTime(entry.createdAt.toUtc())),
              _detail(S.email, entry.email),
              _detail(S.role, entry.role),
              _detail(S.actionLabel, entry.displayAction),
              _detail(S.tableName, entry.entityType),
              _detail('Record ID', entry.entityId),
              if (entry.summary != null && entry.summary!.isNotEmpty)
                _detail('Summary', entry.summary!),
              if (entry.branchId != null) _detail(S.branch, entry.branchId!),
              _detail(
                S.status,
                entry.correctionRequested
                    ? S.pendingApproval
                    : entry.approvedAt != null
                        ? S.approved
                        : 'No correction',
              ),
              if (entry.correctionReason != null &&
                  entry.correctionReason!.isNotEmpty)
                _detail(_reasonHeader, entry.correctionReason!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(S.close),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: value),
            ],
          ),
        ),
      );

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
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                  var shown = filterActivities(entries, _range);
                  if (_statusFilter == S.pendingApproval) {
                    shown = shown.where((e) => e.correctionRequested).toList();
                  }
                  if (shown.isEmpty) {
                    return const EmptyState(message: S.noActivity);
                  }
                  return DataTablePlus(
                    columns: const [
                      S.dateTimeLabel,
                      S.email,
                      S.role,
                      S.actionLabel,
                      S.status,
                      _reasonHeader,
                    ],
                    exportFileName: 'yusra-activity-log.csv',
                    filterChips: const [S.pendingApproval],
                    selectedFilter: _statusFilter,
                    onFilterChanged: (value) =>
                        setState(() => _statusFilter = value),
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
                            IconButton(
                              tooltip: S.view,
                              icon: const Icon(Icons.visibility_outlined,
                                  size: 18),
                              onPressed: () => _showDetails(entry),
                            ),
                            if (isSuper && entry.correctionRequested)
                              IconButton(
                                tooltip: S.approveCorrection,
                                icon: const Icon(Icons.verified_outlined,
                                    size: 18),
                                onPressed: _busy ? null : () => _approve(entry),
                              ),
                            if (!isSuper && !entry.correctionRequested)
                              IconButton(
                                tooltip: S.requestCorrection,
                                icon:
                                    const Icon(Icons.report_outlined, size: 18),
                                onPressed: _busy
                                    ? null
                                    : () => _requestCorrection(entry),
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

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(S.requestCorrection),
      content: Form(
        key: _formKey,
        child: AppTextField(
          label: _reasonHeader,
          controller: _reason,
          maxLines: 4,
          autofocus: true,
          hint: 'Describe what needs to be corrected',
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return S.required;
            if (text.length < _minReasonLength) return _reasonTooShort;
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _reason.text.trim());
          },
          child: const Text(S.confirm),
        ),
      ],
    );
  }
}
