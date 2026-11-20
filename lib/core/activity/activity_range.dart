import '../../core/dates.dart';

enum ActivityRange { all, today, week, month, year }

extension ActivityRangeLabel on ActivityRange {
  String get label => switch (this) {
        ActivityRange.all => 'All time',
        ActivityRange.today => 'Today',
        ActivityRange.week => 'This week',
        ActivityRange.month => 'This month',
        ActivityRange.year => 'This year',
      };
}

/// Inclusive lower bound in UTC for a dashboard range, using Addis Ababa days.
DateTime? activityRangeStart(ActivityRange range, {DateTime? now}) {
  if (range == ActivityRange.all) return null;
  final local = toAddisAbaba(now ?? DateTime.now());
  final DateTime firstLocal;
  switch (range) {
    case ActivityRange.today:
      firstLocal = DateTime(local.year, local.month, local.day);
      break;
    case ActivityRange.week:
      final monday = local.day - (local.weekday - 1);
      firstLocal = DateTime(local.year, local.month, monday);
      break;
    case ActivityRange.month:
      firstLocal = DateTime(local.year, local.month, 1);
      break;
    case ActivityRange.year:
      firstLocal = DateTime(local.year, 1, 1);
      break;
    case ActivityRange.all:
      return null;
  }
  return DateTime.utc(firstLocal.year, firstLocal.month, firstLocal.day)
      .subtract(addisAbabaOffset);
}
