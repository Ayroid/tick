import 'package:flutter_test/flutter_test.dart';
import 'package:tick/analytics.dart';
import 'package:tick/clock.dart';
import 'package:tick/store.dart';
import 'package:tick/usage.dart';

/// A store with a hand-built history and no channel behind it.
///
/// Nothing here calls `load()`: analytics reads two plain fields, so the maths
/// can be tested by filling them in rather than by standing up a fake phone.
TickStore storeWith({
  Map<String, Map<String, int>> archive = const {},
  Map<String, int> todayMs = const {},
  Map<String, Map<String, int>> notifications = const {},
}) {
  final store = TickStore();
  store.archive.addAll(archive);
  store.todayUsage = UsageWindow(
    granted: true,
    byPackage: {
      for (final e in todayMs.entries) e.key: AppUsage(e.key, e.value, 1),
    },
  );
  store.notifications = notifications;
  return store;
}

const minute = 60000;

void main() {
  late DateTime Function() previousClock;

  setUp(() {
    // Thursday 17 September 2026, mid-morning.
    previousClock = useFixedClock(DateTime(2026, 9, 17, 10, 30));
  });

  tearDown(() => clock = previousClock);

  group('spans', () {
    test('a day is one day, ending at the next midnight', () {
      final span = spanOf(Period.day, DateTime(2026, 9, 17));
      expect(span.from, DateTime(2026, 9, 17));
      expect(span.to, DateTime(2026, 9, 18));
    });

    test('a week runs Monday to Monday', () {
      final span = spanOf(Period.week, DateTime(2026, 9, 17));
      expect(span.from, DateTime(2026, 9, 14));
      expect(span.to, DateTime(2026, 9, 21));
    });

    test('a month ends at the first of the next one', () {
      final span = spanOf(Period.month, DateTime(2026, 9, 17));
      expect(span.from, DateTime(2026, 9));
      expect(span.to, DateTime(2026, 10));
    });

    test('December rolls into January rather than month 13', () {
      final span = spanOf(Period.month, DateTime(2026, 12, 5));
      expect(span.to, DateTime(2027, 1));
    });

    test('February keeps its own length', () {
      final span = spanOf(Period.month, DateTime(2028, 2, 10));
      expect(span.to.difference(span.from).inDays, 29);
    });

    test(
      'the previous span is the same number of days, immediately before',
      () {
        final week = spanOf(Period.week, DateTime(2026, 9, 17));
        final before = previousSpan(week);
        expect(before.from, DateTime(2026, 9, 7));
        expect(before.to, DateTime(2026, 9, 14));
      },
    );

    // A month is not a fixed length, so "the previous month" is the same
    // number of days back, not the calendar month before. That is what a
    // like-for-like comparison needs; the alternative compares February with
    // January and calls the shortfall a habit change.
    test('the span before a month is that many days, not the month before', () {
      final month = spanOf(Period.month, DateTime(2026, 9, 17));
      final before = previousSpan(month);
      expect(before.to, DateTime(2026, 9));
      expect(before.to.difference(before.from).inDays, 30);
    });
  });

  group('totals across the seam between archive and today', () {
    final store = storeWith(
      archive: {
        '2026-09-15': {'com.social': 20 * minute},
        '2026-09-16': {'com.social': 10 * minute, 'com.mail': 5 * minute},
      },
      todayMs: {'com.social': 7 * minute},
    );

    test('today comes live, never from the archive', () {
      expect(dayTotals(store, DateTime(2026, 9, 17)), {
        'com.social': 7 * minute,
      });
    });

    test('a finished day comes from the archive', () {
      expect(dayTotals(store, DateTime(2026, 9, 15)), {
        'com.social': 20 * minute,
      });
    });

    test('a day with no record is empty, not an error', () {
      expect(dayTotals(store, DateTime(2026, 9, 10)), isEmpty);
    });

    test('a span adds both sources together', () {
      final totals = appTotals(
        store,
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 18),
      );
      expect(totals['com.social'], 37 * minute);
      expect(totals['com.mail'], 5 * minute);
      expect(sumOf(totals), 42 * minute);
    });

    test('the span end is exclusive — the same day is never counted twice', () {
      final first = appTotals(
        store,
        DateTime(2026, 9, 15),
        DateTime(2026, 9, 16),
      );
      final second = appTotals(
        store,
        DateTime(2026, 9, 16),
        DateTime(2026, 9, 17),
      );
      expect(first.keys, ['com.social']);
      expect(second.keys, containsAll(['com.social', 'com.mail']));
      expect(sumOf(first) + sumOf(second), 35 * minute);
    });

    test('ranked puts the longest first', () {
      final list = ranked(
        appTotals(store, DateTime(2026, 9, 14), DateTime(2026, 9, 18)),
      );
      expect(list.first.package, 'com.social');
      expect(list.last.package, 'com.mail');
    });
  });

  group('the daily series', () {
    test('zero-fills so the bars line up with their labels', () {
      final store = storeWith(
        archive: {
          '2026-09-16': {'com.social': 10 * minute},
        },
        todayMs: {'com.social': 7 * minute},
      );
      final series = dailySeries(
        store,
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 18),
      );
      expect(series.map((d) => d.ms).toList(), [0, 0, 10 * minute, 7 * minute]);
      expect(series.first.day, DateTime(2026, 9, 14));
      expect(series.last.day, DateTime(2026, 9, 17));
    });

    test('a week is seven bars even with nothing in it', () {
      final span = spanOf(Period.week, DateTime(2026, 9, 17));
      expect(dailySeries(storeWith(), span.from, span.to), hasLength(7));
    });
  });

  group('change against the previous span', () {
    test('is null when there is no history to compare with', () {
      final store = storeWith(todayMs: {'com.social': 60 * minute});
      expect(
        changeAgainstPrevious(
          store,
          spanOf(Period.week, DateTime(2026, 9, 17)),
        ),
        isNull,
      );
    });

    test('is a fraction, and can be negative', () {
      final store = storeWith(
        archive: {
          // Last week.
          '2026-09-08': {'com.social': 100 * minute},
          // This week.
          '2026-09-15': {'com.social': 75 * minute},
        },
      );
      final change = changeAgainstPrevious(
        store,
        spanOf(Period.week, DateTime(2026, 9, 17)),
      );
      expect(change, closeTo(-0.25, 0.0001));
    });

    test('an increase reads positive', () {
      final store = storeWith(
        archive: {
          '2026-09-08': {'com.social': 40 * minute},
          '2026-09-15': {'com.social': 60 * minute},
        },
      );
      expect(
        changeAgainstPrevious(
          store,
          spanOf(Period.week, DateTime(2026, 9, 17)),
        ),
        closeTo(0.5, 0.0001),
      );
    });
  });

  group('the budget ring', () {
    test('is nothing at all when no limits are set', () {
      expect(budgetToday(storeWith()), isNull);
    });

    test('is the whole day\'s spend over the whole day\'s budget', () {
      final store = storeWith(
        todayMs: {'com.social': 15 * minute, 'com.mail': 15 * minute},
      );
      store.limits.addAll({'com.social': 30, 'com.mail': 30});
      expect(budgetToday(store), (used: 30 * minute, budget: 60 * minute));
    });

    test('reports the overshoot rather than capping it', () {
      final store = storeWith(todayMs: {'com.social': 45 * minute});
      store.limits['com.social'] = 30;
      final budget = budgetToday(store)!;
      expect(budget.used / budget.budget, closeTo(1.5, 0.0001));
    });

    test('ignores time spent in apps with no limit', () {
      final store = storeWith(
        todayMs: {'com.social': 15 * minute, 'com.mail': 300 * minute},
      );
      store.limits['com.social'] = 30;
      expect(budgetToday(store), (used: 15 * minute, budget: 30 * minute));
    });
  });

  group('notifications', () {
    test('only cover the days the listener was on for', () {
      final store = storeWith(
        notifications: {
          '2026-09-16': {'com.social': 12},
          '2026-09-17': {'com.social': 4, 'com.mail': 9},
        },
      );
      final span = spanOf(Period.week, DateTime(2026, 9, 17));
      expect(notificationTotals(store, span.from, span.to), {
        'com.social': 16,
        'com.mail': 9,
      });
    });

    test('a day before the listener existed contributes nothing', () {
      expect(
        notificationTotals(
          storeWith(),
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 18),
        ),
        isEmpty,
      );
    });
  });

  group('days are calendar days, not 24-hour blocks', () {
    // India has no DST, but the archive is keyed by local date and this is the
    // arithmetic that decides which bucket a day lands in. Using a Duration
    // here would put one day a year into the wrong bucket on any phone that
    // does observe it, and the bug would only reproduce twice a year.
    test('a span across a clock change still has one entry per date', () {
      final store = storeWith();
      // The last Sunday in March, when most of Europe springs forward.
      final series = dailySeries(
        store,
        DateTime(2027, 3, 27),
        DateTime(2027, 3, 30),
      );
      expect(series.map((d) => dayKey(d.day)).toList(), [
        '2027-03-27',
        '2027-03-28',
        '2027-03-29',
      ]);
    });
  });
}
