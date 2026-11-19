import 'package:intl/intl.dart';

/// Addis Ababa is UTC+3 all year round (no DST), so a fixed offset is both
/// correct and independent of the device's timezone database.
const Duration addisAbabaOffset = Duration(hours: 3);

DateTime toAddisAbaba(DateTime value) => value.toUtc().add(addisAbabaOffset);

/// Current time in Africa/Addis_Ababa.
DateTime nowAddisAbaba() => toAddisAbaba(DateTime.now());

String formatDate(DateTime value, {String pattern = 'dd MMM yyyy'}) =>
    DateFormat(pattern, 'en_US').format(toAddisAbaba(value));

String formatDateTime(DateTime value) =>
    formatDate(value, pattern: 'dd MMM yyyy, HH:mm');

String formatTime(DateTime value) => formatDate(value, pattern: 'HH:mm');

String formatIsoDate(DateTime value) =>
    formatDate(value, pattern: 'yyyy-MM-dd');

/// First instant of the day in Addis Ababa time, expressed as UTC.
DateTime startOfAddisDayUtc(DateTime value) {
  final local = toAddisAbaba(value);
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).subtract(addisAbabaOffset);
}

/// Last instant of the day in Addis Ababa time, expressed as UTC.
DateTime endOfAddisDayUtc(DateTime value) =>
    startOfAddisDayUtc(value).add(const Duration(days: 1));

bool isSameAddisDay(DateTime a, DateTime b) {
  final x = toAddisAbaba(a);
  final y = toAddisAbaba(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
