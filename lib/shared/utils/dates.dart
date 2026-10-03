import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Rent dates (move-in, paid until...) are calendar days with no time, stored
// in Postgres as `date` and sent as text like '2026-10-01'. In Dart they are
// DateTime values at midnight; only the year/month/day matter.

/// '2026-10-01' -> DateTime(2026, 10, 1).
DateTime parseDbDate(String value) => DateTime.parse(value);

/// Same, but keeps null as null.
DateTime? parseDbDateOrNull(String? value) => value == null ? null : DateTime.parse(value);

/// DateTime(2026, 10, 1) -> '2026-10-01' (what Postgres expects).
String toDbDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// DateTime(2026, 10, 1) -> '1 Oct 2026' (what people read).
String formatDate(DateTime date) => DateFormat('d MMM yyyy').format(date);

/// Today's date, with the time removed.
DateTime today() => DateUtils.dateOnly(DateTime.now());

/// Whole days from today until [date]: 0 = today, negative = in the past.
/// Uses UTC so a daylight-saving change can't make a day 23 hours long.
int daysUntil(DateTime date) {
  final from = DateTime.utc(today().year, today().month, today().day);
  final to = DateTime.utc(date.year, date.month, date.day);
  return to.difference(from).inDays;
}

/// 'today', 'tomorrow', 'in 5 days', 'yesterday', '3 days ago'.
String relativeDays(DateTime date) {
  final days = daysUntil(date);
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  if (days > 1) return 'in $days days';
  return '${-days} days ago';
}

/// [date] plus [months] calendar months, the same way Postgres does it:
/// if the day doesn't exist in the target month, use that month's last day.
/// 31 Jan + 1 month = 28 Feb (29 in a leap year); 31 Jan + 2 months = 31 Mar.
DateTime addMonths(DateTime date, int months) {
  final monthIndex = date.month - 1 + months; // 0-based, may pass 12
  final year = date.year + (monthIndex ~/ 12);
  final month = monthIndex % 12 + 1;
  // Day 0 of the next month = the last day of this month.
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}

/// Time from today until [date] in words: '2 months 5 days', '12 days',
/// '1 day', 'today'. A date in the past gives the time since, the same way.
String timeLeftText(DateTime date) {
  final now = today();
  final target = DateUtils.dateOnly(date);
  final start = target.isBefore(now) ? target : now;
  final end = target.isBefore(now) ? now : target;

  // Whole calendar months first (like rent periods), then the days left over.
  var months = 0;
  while (!addMonths(start, months + 1).isAfter(end)) {
    months++;
  }
  final afterMonths = addMonths(start, months);
  // UTC so a daylight-saving change can't make a day 23 hours long.
  final days = DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(afterMonths.year, afterMonths.month, afterMonths.day))
      .inDays;

  String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  if (months == 0 && days == 0) return 'today';
  if (months == 0) return plural(days, 'day');
  if (days == 0) return plural(months, 'month');
  return '${plural(months, 'month')} ${plural(days, 'day')}';
}
