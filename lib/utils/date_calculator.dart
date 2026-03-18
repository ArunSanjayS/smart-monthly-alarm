/// ─────────────────────────────────────────────────────────────────────────────
/// DateCalculator
///
/// All date arithmetic for the "Nth weekday of month" alarm rule.
///
/// WEEKDAY CONVENTION (ISO 8601)
///   Monday = 1, Tuesday = 2, …, Sunday = 7
///   This matches Dart's [DateTime.weekday].
///
/// WEEK-OF-MONTH CONVENTION
///   0 = First   (1st occurrence in month)
///   1 = Second
///   2 = Third
///   3 = Fourth
///   4 = Last    (last occurrence regardless of how many there are)
///
/// TRIGGER DATE RULE
///   triggerDate = ruleDate − 2 days
///   The trigger date MAY fall in the *previous* month; this is handled
///   correctly – we never skip or shift such an alarm.
/// ─────────────────────────────────────────────────────────────────────────────
class DateCalculator {
  // ─── Public API ────────────────────────────────────────────────────────────

  /// Returns the next trigger [DateTime] strictly after [now].
  ///
  /// Scans current month first, then up to 13 future months so that an
  /// alarm whose trigger date falls in the *previous* calendar month is
  /// never missed when scanning forward.
  static DateTime? getNextTriggerDate({
    required DateTime now,
    required int weekOfMonth,
    required int dayOfWeek,
    required int hour,
    required int minute,
  }) {
    // We check:
    //   • The month BEFORE the current month (because the trigger for a
    //     "first day of next month" rule may already have landed in the
    //     previous month but still be in the future relative to 'now').
    //   • The current month.
    //   • Up to 12 future months.
    for (int offset = -1; offset <= 12; offset++) {
      final probe = _addMonths(DateTime(now.year, now.month), offset);
      final trigger = computeTriggerDate(
        year: probe.year,
        month: probe.month,
        weekOfMonth: weekOfMonth,
        dayOfWeek: dayOfWeek,
        hour: hour,
        minute: minute,
      );
      if (trigger != null && trigger.isAfter(now)) {
        return trigger;
      }
    }
    return null;
  }

  /// Computes the "2-days-before" trigger [DateTime] for the [weekOfMonth] /
  /// [dayOfWeek] rule applied to [year] / [month].
  ///
  /// Returns `null` when the Nth occurrence does not exist in that month
  /// (e.g. 5th Monday in a month that has only 4 Mondays – treated the same
  /// as "Fourth" which *does* exist, but we return null to let callers skip).
  static DateTime? computeTriggerDate({
    required int year,
    required int month,
    required int weekOfMonth,
    required int dayOfWeek,
    required int hour,
    required int minute,
  }) {
    final ruleDay = _getNthWeekdayOfMonth(
      year: year,
      month: month,
      weekOfMonth: weekOfMonth,
      dayOfWeek: dayOfWeek,
    );
    if (ruleDay == null) return null;

    // Set the exact clock time on the rule date, then subtract 2 days.
    final ruleDateTime =
        DateTime(ruleDay.year, ruleDay.month, ruleDay.day, hour, minute);
    return ruleDateTime.subtract(const Duration(days: 2));
  }

  // ─── Internal helpers ───────────────────────────────────────────────────────

  /// Returns the [weekOfMonth]-th occurrence of [dayOfWeek] in [year]/[month].
  ///
  /// [dayOfWeek]   – ISO weekday (Mon=1 … Sun=7).
  /// [weekOfMonth] – 0=First … 3=Fourth, 4=Last.
  ///
  /// Returns `null` if the Nth occurrence does not exist in that month.
  static DateTime? _getNthWeekdayOfMonth({
    required int year,
    required int month,
    required int weekOfMonth,
    required int dayOfWeek,
  }) {
    if (weekOfMonth == 4) {
      return _getLastWeekdayOfMonth(year: year, month: month, dayOfWeek: dayOfWeek);
    }

    // ── Find the first occurrence of [dayOfWeek] in this month ──────────────
    final firstOfMonth = DateTime(year, month, 1);
    // How many days to add to reach the desired weekday?
    int daysToAdd = dayOfWeek - firstOfMonth.weekday;
    if (daysToAdd < 0) daysToAdd += 7;

    final firstOccurrence = firstOfMonth.add(Duration(days: daysToAdd));

    // ── Jump forward by [weekOfMonth] complete weeks ─────────────────────────
    final nthOccurrence = firstOccurrence.add(Duration(days: weekOfMonth * 7));

    // Guard: still within the requested month?
    if (nthOccurrence.month != month) return null;

    return nthOccurrence;
  }

  /// Returns the LAST occurrence of [dayOfWeek] in [year]/[month].
  static DateTime _getLastWeekdayOfMonth({
    required int year,
    required int month,
    required int dayOfWeek,
  }) {
    // Day 0 of the following month == last day of [month].
    final lastOfMonth = DateTime(year, month + 1, 0);
    int daysToSubtract = lastOfMonth.weekday - dayOfWeek;
    if (daysToSubtract < 0) daysToSubtract += 7;
    return lastOfMonth.subtract(Duration(days: daysToSubtract));
  }

  /// Safely add [months] (can be negative) to a [DateTime], clamping to the
  /// last valid day of the target month.
  static DateTime _addMonths(DateTime dt, int months) {
    int totalMonths = dt.month - 1 + months;
    final int year = dt.year + totalMonths ~/ 12;
    final int month = (totalMonths % 12) + 1;
    // Clamp day to the last day of the target month.
    final int lastDay = DateTime(year, month + 1, 0).day;
    final int day = dt.day.clamp(1, lastDay);
    return DateTime(year, month, day);
  }

  // ─── Human-readable helpers ─────────────────────────────────────────────────

  static String describeRule({
    required int weekOfMonth,
    required int dayOfWeek,
  }) {
    const weeks = ['First', 'Second', 'Third', 'Fourth', 'Last'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${weeks[weekOfMonth]} ${days[dayOfWeek - 1]}';
  }
}
