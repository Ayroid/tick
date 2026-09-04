import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tick/clock.dart';
import 'package:tick/store.dart';

const _channel = MethodChannel('com.ayroid.tick/native');

/// Every call the store made down the channel, in order — so a test can assert
/// that a rule change actually reached the guard and not just the disk.
final calls = <MethodCall>[];

/// A phone, as far as the store is concerned.
///
/// [usage] is per-day, keyed the way the archive is; a day not listed simply
/// has no records, which is also what a real device returns for a day that has
/// aged out of the event stream.
void mockNative({
  bool usageGranted = true,
  bool accessibility = true,
  Map<String, Map<String, int>> usage = const {},
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'permissions':
            return {
              'usage': usageGranted,
              'accessibility': accessibility,
              'notifications': false,
              'postNotifications': true,
            };
          case 'apps':
            return [
              {'package': 'com.social', 'label': 'Social', 'icon': null},
              {'package': 'com.mail', 'label': 'Mail', 'icon': null},
            ];
          case 'usage':
            if (!usageGranted) return {'granted': false};
            final start = DateTime.fromMillisecondsSinceEpoch(
              call.arguments['start'] as int,
            );
            final day = usage[dayKey(start)] ?? const {};
            return {
              'granted': true,
              'unlocks': 7,
              'byPackage': {
                for (final e in day.entries) e.key: {'ms': e.value, 'opens': 3},
              },
            };
          case 'notifications':
            return '{}';
          default:
            return null;
        }
      });
}

Future<TickStore> loaded() async {
  final store = TickStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime Function() previousClock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    // A Thursday, mid-morning, mid-month.
    previousClock = useFixedClock(DateTime(2026, 9, 17, 10, 30));
    mockNative();
  });

  tearDown(() {
    clock = previousClock;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('day keys', () {
    test('are zero-padded so lexical order is chronological', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      final keys = [
        dayKey(DateTime(2026, 9, 9)),
        dayKey(DateTime(2026, 10, 1)),
        dayKey(DateTime(2026, 9, 10)),
      ]..sort();
      expect(keys, ['2026-09-09', '2026-09-10', '2026-10-01']);
    });

    test('round-trip through parseDay', () {
      final d = DateTime(2026, 2, 29);
      expect(parseDay(dayKey(d)), d);
    });

    test('day arithmetic crosses a month and a year', () {
      expect(dayKey(shiftDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
      expect(dayKey(shiftDays(DateTime(2026, 3, 1), -1)), '2026-02-28');
    });

    test('a week starts on Monday', () {
      // The 17th is a Thursday.
      expect(startOfWeek(DateTime(2026, 9, 17)), DateTime(2026, 9, 14));
      expect(startOfWeek(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
    });

    test('ids never collide inside one tight loop', () {
      final ids = {for (var i = 0; i < 500; i++) newId()};
      expect(ids, hasLength(500));
    });
  });

  group('schedules', () {
    Schedule at(String from, String to, {List<int> days = const []}) =>
        Schedule(
          id: 'x',
          name: 'Bedtime',
          packages: {'com.social'},
          days: days,
          from: from,
          to: to,
        );

    test('an ordinary window covers only the hours inside it', () {
      final work = at('09:00', '17:00');
      expect(work.activeAt(DateTime(2026, 9, 17, 12)), isTrue);
      expect(work.activeAt(DateTime(2026, 9, 17, 8, 59)), isFalse);
      expect(work.activeAt(DateTime(2026, 9, 17, 17)), isFalse);
    });

    test('a window that wraps midnight covers both halves', () {
      final bedtime = at('22:00', '07:00');
      expect(bedtime.activeAt(DateTime(2026, 9, 17, 23)), isTrue);
      expect(bedtime.activeAt(DateTime(2026, 9, 17, 3)), isTrue);
      expect(bedtime.activeAt(DateTime(2026, 9, 17, 12)), isFalse);
    });

    // The one that is easy to get wrong: 3am on Saturday belongs to Friday's
    // bedtime, not to Saturday's.
    test('the half after midnight belongs to the previous day', () {
      final fridayNight = at('22:00', '07:00', days: [5]);
      expect(fridayNight.activeAt(DateTime(2026, 9, 18, 23)), isTrue);
      expect(fridayNight.activeAt(DateTime(2026, 9, 19, 3)), isTrue);
      expect(fridayNight.activeAt(DateTime(2026, 9, 19, 23)), isFalse);
      expect(fridayNight.activeAt(DateTime(2026, 9, 18, 3)), isFalse);
    });

    test('no days listed means every day', () {
      final always = at('22:00', '23:00');
      for (var d = 14; d <= 20; d++) {
        expect(always.activeAt(DateTime(2026, 9, d, 22, 30)), isTrue);
      }
    });

    test('a disabled schedule is never active', () {
      expect(
        at(
          '09:00',
          '17:00',
        ).copyWith(enabled: false).activeAt(DateTime(2026, 9, 17, 12)),
        isFalse,
      );
    });

    test('a zero-length window blocks nothing', () {
      expect(at('09:00', '09:00').activeAt(DateTime(2026, 9, 17, 9)), isFalse);
    });
  });

  group('focus sessions', () {
    test('expire on their own, with no timer and nothing to clean up', () {
      final store = TickStore()..startFocus(const Duration(minutes: 30), {'a'});
      expect(store.focus.active, isTrue);
      expect(store.focus.left, const Duration(minutes: 30));

      clock = () => DateTime(2026, 9, 17, 11, 30);
      expect(store.focus.active, isFalse);
      expect(store.focus.left, Duration.zero);
    });

    test('a session over no apps is not a session', () {
      final store = TickStore()
        ..startFocus(const Duration(minutes: 30), <String>{});
      expect(store.focus.active, isFalse);
    });
  });

  group('what is blocked, and why', () {
    test('nothing, when nothing has been set', () async {
      final store = await loaded();
      expect(store.blockReason('com.social'), isNull);
    });

    test('a limit blocks once it is spent, and not before', () async {
      mockNative(
        usage: {
          '2026-09-17': {'com.social': 29 * 60000},
        },
      );
      final store = await loaded();
      store.setLimit('com.social', 30);
      expect(store.blockReason('com.social'), isNull);

      store.setLimit('com.social', 25);
      expect(store.blockReason('com.social'), 'Daily limit');
    });

    test('a schedule blocks regardless of how little it has been used', () {
      final store = TickStore()
        ..saveSchedule(
          Schedule(
            id: 'a',
            name: 'Bedtime',
            packages: {'com.social'},
            days: const [],
            from: '09:00',
            to: '17:00',
          ),
        );
      expect(store.blockReason('com.social'), 'Bedtime');
      expect(store.blockReason('com.mail'), isNull);
    });

    test('a focus session names itself', () {
      final store = TickStore()
        ..startFocus(const Duration(minutes: 25), {'com.social'});
      expect(store.blockReason('com.social'), 'Focus session');
    });

    test('a limit can be raised while it is blocking — by design', () async {
      mockNative(
        usage: {
          '2026-09-17': {'com.social': 31 * 60000},
        },
      );
      final store = await loaded();
      store.setLimit('com.social', 30);
      expect(store.blockReason('com.social'), 'Daily limit');

      store.setLimit('com.social', 60);
      expect(store.blockReason('com.social'), isNull);
    });

    test('removing a limit takes the row away entirely', () {
      final store = TickStore()..setLimit('com.social', 30);
      expect(store.limits, contains('com.social'));
      store.setLimit('com.social', 0);
      expect(store.limits, isEmpty);
    });
  });

  group('the guard hears about every rule change', () {
    test('a limit reaches the native side, not just the disk', () async {
      final store = await loaded();
      calls.clear();
      store.setLimit('com.social', 45);

      final rules = calls.firstWhere((c) => c.method == 'setRules');
      expect(jsonDecode(rules.arguments as String), {
        'limits': {'com.social': 45},
        'schedules': <dynamic>[],
        'focus': {'until': 0, 'packages': <dynamic>[]},
      });
    });

    test('so does a focus session', () async {
      final store = await loaded();
      calls.clear();
      store.startFocus(const Duration(minutes: 20), {'com.social'});

      final rules = jsonDecode(
        calls.lastWhere((c) => c.method == 'setRules').arguments as String,
      );
      expect(rules['focus']['packages'], ['com.social']);
      expect(
        rules['focus']['until'],
        DateTime(2026, 9, 17, 10, 50).millisecondsSinceEpoch,
      );
    });
  });

  group('persistence', () {
    test('rules come back on the next launch', () async {
      final first = await loaded();
      first.setLimit('com.social', 30);
      first.saveSchedule(
        Schedule(
          id: 'a',
          name: 'Bedtime',
          packages: {'com.social'},
          days: const [1, 2],
          from: '22:00',
          to: '07:00',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final second = await loaded();
      expect(second.limits, {'com.social': 30});
      expect(second.schedules.single.name, 'Bedtime');
      expect(second.schedules.single.days, [1, 2]);
      expect(second.schedules.single.from, '22:00');
    });

    test('corrupt rules start empty and do not brick the launch', () async {
      SharedPreferences.setMockInitialValues({'rules': 'not json at all'});
      final store = await loaded();
      expect(store.loaded, isTrue);
      expect(store.limits, isEmpty);

      // The bad string is left where it is, so it can still be recovered.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rules'), 'not json at all');
    });

    test('a hand-edited limit is clamped rather than trusted', () async {
      SharedPreferences.setMockInitialValues({
        'rules': jsonEncode({
          'limits': {'com.social': 99999, 'com.mail': -4},
        }),
      });
      final store = await loaded();
      expect(store.limits['com.social'], 24 * 60);
      expect(store.limits['com.mail'], 1);
    });

    test('a schedule missing every field still loads', () async {
      SharedPreferences.setMockInitialValues({
        'rules': jsonEncode({
          'schedules': [<String, dynamic>{}],
        }),
      });
      final store = await loaded();
      final schedule = store.schedules.single;
      expect(schedule.name, 'Schedule');
      expect(schedule.from, '00:00');
      expect(schedule.packages, isEmpty);
      expect(schedule.activeAt(DateTime(2026, 9, 17, 3)), isFalse);
    });
  });

  group('the archive', () {
    test('catches up every finished day since the last one', () async {
      mockNative(
        usage: {
          '2026-09-15': {'com.social': 20 * 60000},
          '2026-09-16': {'com.mail': 5 * 60000},
          '2026-09-17': {'com.social': 60000},
        },
      );
      final store = await loaded();

      expect(store.archive['2026-09-15'], {'com.social': 20 * 60000});
      expect(store.archive['2026-09-16'], {'com.mail': 5 * 60000});
      // Today is never archived — it is not finished, and it reads live.
      expect(store.archive.containsKey('2026-09-17'), isFalse);
      expect(store.lastArchived, '2026-09-16');
    });

    test('a glance is not worth a row', () async {
      mockNative(
        usage: {
          '2026-09-16': {'com.social': 59 * 1000, 'com.mail': 61 * 1000},
        },
      );
      final store = await loaded();
      expect(store.archive['2026-09-16'], {'com.mail': 61 * 1000});
    });

    test('a second launch on the same day does not redo the work', () async {
      mockNative(
        usage: {
          '2026-09-16': {'com.mail': 5 * 60000},
        },
      );
      await loaded();

      calls.clear();
      await loaded();
      final windows = calls
          .where((c) => c.method == 'usage')
          .map((c) => c.arguments['start'] as int)
          .toList();
      // Only today's live read; every finished day is already in.
      expect(windows, [DateTime(2026, 9, 17).millisecondsSinceEpoch]);
    });

    test(
      'without usage access nothing is read and nothing is claimed',
      () async {
        mockNative(usageGranted: false);
        final store = await loaded();
        expect(store.todayUsage.granted, isFalse);
        expect(store.archive, isEmpty);
        expect(store.lastArchived, '');
      },
    );
  });

  group('backup', () {
    Map<String, dynamic> content(String raw) =>
        jsonDecode(raw) as Map<String, dynamic>..remove('exportedAt');

    test('export then import is a round trip', () async {
      final first = await loaded();
      first.setLimit('com.social', 30);
      first.saveSchedule(
        Schedule(
          id: 'a',
          name: 'Bedtime',
          packages: {'com.social'},
          days: const [6, 7],
          from: '22:00',
          to: '07:00',
        ),
      );
      final backup = first.exportJson();

      final second = TickStore();
      expect(second.importJson(backup), isTrue);
      expect(content(second.exportJson()), content(backup));
    });

    test('a malformed file is rejected and changes nothing', () async {
      final store = await loaded();
      store.setLimit('com.social', 30);

      expect(store.importJson('{ this is not json'), isFalse);
      expect(store.limits, {'com.social': 30});
    });

    test('an empty document is a valid empty backup', () {
      final store = TickStore()..setLimit('com.social', 30);
      expect(store.importJson('{}'), isTrue);
      expect(store.limits, isEmpty);
      expect(store.schedules, isEmpty);
    });

    test('a negative archived duration cannot come back', () {
      final store = TickStore();
      expect(
        store.importJson(
          jsonEncode({
            'archive': {
              '2026-09-16': {'com.social': -5000},
            },
          }),
        ),
        isTrue,
      );
      expect(store.archive['2026-09-16'], {'com.social': 0});
    });
  });

  group('reading', () {
    test('an uninstalled app still has a name to show', () async {
      final store = await loaded();
      expect(store.labelOf('com.social'), 'Social');
      expect(store.labelOf('com.gone'), 'com.gone');
    });

    test('limited apps sort by how much of the budget is gone', () async {
      mockNative(
        usage: {
          '2026-09-17': {'com.social': 5 * 60000, 'com.mail': 20 * 60000},
        },
      );
      final store = await loaded();
      store.setLimit('com.social', 60);
      store.setLimit('com.mail', 30);
      // Mail is two thirds gone, Social one twelfth.
      expect(store.limitedPackages, ['com.mail', 'com.social']);
    });
  });
}
