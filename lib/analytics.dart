/// The maths, kept out of the screens that draw it.
///
/// Every function here reads two sources and merges them: [TickStore.archive]
/// for days that are finished, and [TickStore.todayUsage] for today, which is
/// live from the system and never archived. Getting that seam right in one
/// place is the reason this file exists — a screen that reached for the
/// archive directly would show today as empty until midnight.
library;

import 'store.dart';
import 'usage.dart';

enum Period { day, week, month }

/// The half-open span a period covers, anchored on [on].
///
/// The end is the start of the *next* day, so a span always contains whole
/// local days and today's span includes the hours still to come. Half-open
/// because two adjacent spans must not both contain the same midnight.
({DateTime from, DateTime to}) spanOf(Period period, DateTime on) =>
    switch (period) {
      Period.day => (from: on, to: shiftDays(on, 1)),
      Period.week => (from: startOfWeek(on), to: shiftDays(startOfWeek(on), 7)),
      Period.month => (
        from: startOfMonth(on),
        to: DateTime(on.year, on.month + 1),
      ),
    };

/// The span immediately before [span], of the same length in days — what
/// "down 12% on last week" is measured against.
({DateTime from, DateTime to}) previousSpan(
  ({DateTime from, DateTime to}) span,
) {
  final days = span.to.difference(span.from).inDays;
  return (from: shiftDays(span.from, -days), to: span.from);
}

/// One day's totals, from whichever source owns that day.
Map<String, int> dayTotals(TickStore store, DateTime day) {
  if (day == today()) {
    return {
      for (final app in store.todayUsage.byPackage.values) app.package: app.ms,
    };
  }
  return store.archive[dayKey(day)] ?? const {};
}

/// Milliseconds per package across [from, to).
Map<String, int> appTotals(TickStore store, DateTime from, DateTime to) {
  final totals = <String, int>{};
  for (var day = from; day.isBefore(to); day = shiftDays(day, 1)) {
    dayTotals(store, day).forEach((package, ms) {
      totals[package] = (totals[package] ?? 0) + ms;
    });
  }
  return totals;
}

/// Longest first — the order every screen wants.
List<AppUsage> ranked(Map<String, int> totals) {
  final list = [for (final e in totals.entries) AppUsage(e.key, e.value, 0)]
    ..sort((a, b) => b.ms.compareTo(a.ms));
  return list;
}

int sumOf(Map<String, int> totals) =>
    totals.values.fold(0, (sum, ms) => sum + ms);

/// One total per day across [from, to), oldest first — the bar chart.
///
/// Days with no record come back as 0 rather than being skipped, so the bars
/// line up with their labels. A gap in the archive and a day you genuinely did
/// not touch the phone are indistinguishable here, and that is honest: the
/// archive cannot tell them apart either.
List<({DateTime day, int ms})> dailySeries(
  TickStore store,
  DateTime from,
  DateTime to,
) {
  final series = <({DateTime day, int ms})>[];
  for (var day = from; day.isBefore(to); day = shiftDays(day, 1)) {
    series.add((day: day, ms: sumOf(dayTotals(store, day))));
  }
  return series;
}

/// The change from the previous span of the same length, as a fraction:
/// `-0.12` is 12% less time than last week.
///
/// Null when there is nothing to compare against. A period with no history
/// behind it is not "up 100%", it is unknown, and a screen that prints a
/// number here would be inventing one.
double? changeAgainstPrevious(
  TickStore store,
  ({DateTime from, DateTime to}) span,
) {
  final before = previousSpan(span);
  final was = sumOf(appTotals(store, before.from, before.to));
  if (was == 0) return null;
  final now = sumOf(appTotals(store, span.from, span.to));
  return (now - was) / was;
}

/// Notification counts per package across [from, to).
///
/// Only ever covers days since the listener was switched on — there is no
/// history to backfill, and a low number early on means "not counted yet"
/// rather than "quiet".
Map<String, int> notificationTotals(
  TickStore store,
  DateTime from,
  DateTime to,
) {
  final totals = <String, int>{};
  for (var day = from; day.isBefore(to); day = shiftDays(day, 1)) {
    store.notifications[dayKey(day)]?.forEach((package, count) {
      totals[package] = (totals[package] ?? 0) + count;
    });
  }
  return totals;
}

/// Today's spend against the limits set for it, in milliseconds.
///
/// Both halves, not a ratio: the ring needs the fraction but the caption
/// under it needs the two real numbers, and a screen that shows a percentage
/// beside a duration it does not divide is a screen showing two different
/// quantities and hoping nobody checks.
///
/// Null when nothing is limited — a ring with no budget behind it is a
/// decoration pretending to be a measurement.
({int used, int budget})? budgetToday(TickStore store) {
  if (store.limits.isEmpty) return null;
  var budget = 0, used = 0;
  store.limits.forEach((package, minutes) {
    budget += minutes * 60000;
    used += store.usedTodayMs(package);
  });
  return budget == 0 ? null : (used: used, budget: budget);
}
