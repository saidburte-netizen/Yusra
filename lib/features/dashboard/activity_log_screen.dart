import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/activity/activity.dart';
import '../../core/activity/activity_range.dart';
import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/strings.dart';
import '../../core/widgets.dart';

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  ActivityRange _range = ActivityRange.today;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityProvider);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.activity,
              subtitle: 'Activity log',
              actions: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<ActivityRange>(
                    value: _range,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: S.timeRange),
                    items: [
                      for (final r in ActivityRange.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (v) => setState(() => _range = v ?? ActivityRange.today),
                  ),
                ),
                IconButton(onPressed: () => ref.invalidate(activityProvider), icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorState(message: AppErrorMapper.from(e).message, onRetry: () => ref.invalidate(activityProvider)),
                data: (entries) {
                  final filtered = filterActivities(entries, _range);
                  if (filtered.isEmpty) {
                    return const EmptyState(message: S.noActivity, icon: Icons.history);
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = filtered[i];
                      return ListTile(
                        title: Text(entry.displayAction),
                        subtitle: Text('${entry.email} · ${entry.role}'),
                        trailing: Text(formatDateTime(entry.createdAt.toUtc())),
                      );
                    },
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
