import 'package:flutter_test/flutter_test.dart';
import 'package:yusra_pharmacy/core/dates.dart';

void main() {
  test('Addis Ababa is UTC+3 with no DST', () {
    expect(toAddisAbaba(DateTime.utc(2024, 1, 1, 21)), DateTime.utc(2024, 1, 2));
    expect(toAddisAbaba(DateTime.utc(2024, 7, 1, 21)), DateTime.utc(2024, 7, 2));
  });

  test('day boundaries use Addis midnight, not UTC midnight', () {
    // 22:00 UTC is already 01:00 the next day in Addis.
    final start = startOfAddisDayUtc(DateTime.utc(2024, 1, 1, 22));
    expect(start, DateTime.utc(2024, 1, 1, 21));
    expect(endOfAddisDayUtc(DateTime.utc(2024, 1, 1, 22)),
        DateTime.utc(2024, 1, 2, 21));
  });

  test('isSameAddisDay groups times across the UTC boundary', () {
    expect(
      isSameAddisDay(DateTime.utc(2024, 1, 1, 21), DateTime.utc(2024, 1, 2, 20)),
      isTrue,
    );
    expect(
      isSameAddisDay(DateTime.utc(2024, 1, 1, 20), DateTime.utc(2024, 1, 1, 21)),
      isFalse,
    );
  });

  test('formatting converts to local wall-clock time', () {
    final value = DateTime.utc(2024, 1, 1, 21);
    expect(formatDate(value), '02 Jan 2024');
    expect(formatIsoDate(value), '2024-01-02');
    expect(formatTime(value), '00:00');
    expect(formatDateTime(value), '02 Jan 2024, 00:00');
  });
}
