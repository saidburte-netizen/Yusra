import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_error.dart';
import '../state/invalidation.dart';
import 'feedback.dart';

/// One shared row action. Callers decide visibility from the permission matrix
/// ([allowed]); the widget owns confirmation, feedback, audit and refresh.
///
/// Audit is *not* inserted from the client: `audit_logs` is select-only for
/// authenticated users. Every action below must go through a table write
/// (the `audit_row()` trigger) or an existing SECURITY DEFINER RPC that writes
/// its own audit row, so exactly one audit entry is produced per action.
class RowAction {
  const RowAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.allowed = true,
    this.confirmTitle,
    this.confirmMessage,
    this.successMessage,
    this.danger = false,
    this.mutation,
  });

  final String label;
  final IconData icon;

  /// Performs the write. Must use an existing table/RPC path so SQL audit
  /// triggers record it. Return a String to override [successMessage].
  final Future<String?> Function() onSelected;

  /// Set false to hide the action for the current role/record state.
  final bool allowed;
  final String? confirmTitle;
  final String? confirmMessage;
  final String? successMessage;
  final bool danger;

  /// Mutation name from the central invalidation graph. Defaults to a generic
  /// row action that refreshes the dashboard, activity and common lists.
  final String? mutation;
}

/// A single `⋮` menu for every record row on phone and desktop.
class RowActions extends ConsumerWidget {
  const RowActions({super.key, required this.actions, this.tooltip = 'Actions'});

  final List<RowAction> actions;
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = actions.where((action) => action.allowed).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<RowAction>(
      tooltip: tooltip,
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        for (final action in visible)
          PopupMenuItem<RowAction>(
            value: action,
            child: Row(
              children: [
                Icon(action.icon,
                    size: 18,
                    color: action.danger ? Theme.of(context).colorScheme.error : null),
                const SizedBox(width: 10),
                Expanded(child: Text(action.label)),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, RowAction action) async {
    if (action.confirmTitle != null && action.confirmMessage != null) {
      final ok = await showConfirmDialog(
        context,
        title: action.confirmTitle!,
        message: action.confirmMessage!,
        danger: action.danger,
      );
      if (ok != true) return;
    }
    try {
      final message = await action.onSelected();
      // The SQL trigger/RPC already wrote the audit row; refresh every list
      // and the dashboard through the single source of truth.
      ref.applyMutation(action.mutation ?? Mutation.rowAction);
      if (!context.mounted) return;
      final text = message ?? action.successMessage;
      if (text != null && text.isNotEmpty) AppSnackbar.success(context, text);
    } catch (e) {
      if (!context.mounted) return;
      AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}
