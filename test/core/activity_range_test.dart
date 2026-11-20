import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/activity/activity.dart';
import 'package:yusra_pharmacy/core/activity/activity_range.dart';

ActivityEntry entry(String id, DateTime at) => ActivityEntry(
      id: id,
      email: 'staff@example.com',
      role: 'cashier',
      action: 'INSERT',
      entityType: 'sales',
      entityId: id,
      createdAt: at,
    );

void main() {
  group('dashboard activity ranges', () {
    // 12:30 UTC = 15:30 Addis, same calendar day.
    final now = DateTime.utc(2026, 11, 20, 12, 30);

    test('all time keeps every record', () {
      expect(activityRangeStart(ActivityRange.all, now: now), isNull);
      final entries = [entry('a', DateTime.utc(2020))];
      expect(filterActivities(entries, ActivityRange.all, now: now), entries);
    });

    test('today starts at Addis midnight', () {
      final start = activityRangeStart(ActivityRange.today, now: now);
      expect(start, DateTime.utc(2026, 11, 19, 21));
      final entries = [
        entry('old', DateTime.utc(2026, 11, 19, 20, 59)),
        entry('new', DateTime.utc(2026, 11, 19, 21)),
      ];
      expect(filterActivities(entries, ActivityRange.today, now: now).single.id,
          'new');
    });

    test('week starts on Monday in Addis', () {
      final start = activityRangeStart(ActivityRange.week, now: now);
      // 20 Nov 2026 is a Friday; Monday is 16 Nov.
      expect(start, DateTime.utc(2026, 11, 15, 21));
    });

    test('month and year boundaries', () {
      expect(activityRangeStart(ActivityRange.month, now: now),
          DateTime.utc(2026, 10, 31, 21));
      expect(activityRangeStart(ActivityRange.year, now: now),
          DateTime.utc(2025, 12, 31, 21));
    });
  });
}
