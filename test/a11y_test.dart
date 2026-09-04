import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tick/clock.dart';
import 'package:tick/home.dart';
import 'package:tick/insights_screen.dart';
import 'package:tick/limits_screen.dart';
import 'package:tick/main.dart';
import 'package:tick/store.dart';

import 'fake_phone.dart';

const minute = 60000;

/// Contrast is deliberately NOT asserted here.
///
/// `textContrastGuideline` measures a rendered pixel against whatever it
/// believes the background is, and it gets a selected pill wrong every time —
/// it reads the label against the track rather than against the pill that is
/// actually behind it, and fails a pair that measures 4.64:1 by hand. Every
/// contrast pair in this app is asserted analytically, per pair and per theme,
/// in test/palette_test.dart instead.
void main() {
  late DateTime Function() previousClock;

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    previousClock = useFixedClock(DateTime(2026, 9, 17, 10, 30));
    mockNative(
      usage: {
        '2026-09-17': {'com.social': 42 * minute, 'com.mail': 8 * minute},
      },
    );
  });

  tearDown(() {
    clock = previousClock;
    unmockNative();
  });

  Future<TickStore> ready(WidgetTester tester) async {
    phone(tester);
    final store = TickStore();
    await store.load();
    await tester.pump();
    return store;
  }

  group('icon-only controls carry their name twice', () {
    // A tooltip is for a person who can see the glyph and does not recognise
    // it; a semantics label is for someone who never sees it at all. Neither
    // substitutes for the other, so every icon button has both.
    testWidgets('on Today', (tester) async {
      final store = await ready(tester);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    });

    testWidgets('on Limits', (tester) async {
      final store = await ready(tester);
      store.setLimit('com.social', 60);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();

      for (final label in ['Add a limit', 'Start a focus session']) {
        expect(find.byTooltip(label), findsOneWidget, reason: '$label tooltip');
        // RegExp, because a button inside a card is announced as part of that
        // card's block rather than as a stop of its own — which is the right
        // reading order, and still carries the words.
        expect(
          find.bySemanticsLabel(RegExp(label)),
          findsOneWidget,
          reason: '$label semantics',
        );
      }

      // Below the fold, and a ListView does not build what it is not showing.
      await tester.scrollUntilVisible(find.byTooltip('Add a schedule'), 200);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Add a schedule')), findsOneWidget);
    });
  });

  group('tap targets', () {
    Future<void> check(WidgetTester tester, Widget screen) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(screen);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    }

    testWidgets('Today', (tester) async {
      final store = await ready(tester);
      await check(
        tester,
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
    });

    testWidgets('Limits, with rules in it', (tester) async {
      final store = await ready(tester);
      store.setLimit('com.social', 60);
      store.saveSchedule(
        Schedule(
          id: 'a',
          name: 'Bedtime',
          packages: {'com.mail'},
          days: const [],
          from: '22:00',
          to: '07:00',
        ),
      );
      await check(tester, page(store, () => LimitsPage(store: store)));
    });

    testWidgets('Insights', (tester) async {
      final store = await ready(tester);
      await check(tester, page(store, () => InsightsPage(store: store)));
    });

    testWidgets('the shell, including the floating tab pill', (tester) async {
      await ready(tester);
      await check(tester, const App());
    });
  });

  group('rows announce once, not five times', () {
    testWidgets('an app row is one stop with everything in it', (tester) async {
      final store = await ready(tester);
      final handle = tester.ensureSemantics();
      store.setLimit('com.social', 60);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      // Name, duration and the note, in one announcement — not an icon stop,
      // a label stop, a number stop and a bar stop.
      expect(
        find.bySemanticsLabel('Social, 42m, 18m left of 1h'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a chip says in words what its glyph says in colour', (
      tester,
    ) async {
      final store = await ready(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      // The hero announces as one block — the total, then each chip — rather
      // than as four separate stops, so these are matched inside it.
      expect(find.bySemanticsLabel(RegExp('7 unlocks today')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('2 apps used')), findsOneWidget);
      handle.dispose();
    });
  });

  group('selection is announced, not only coloured', () {
    testWidgets('the period picker', (tester) async {
      final store = await ready(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(store, () => InsightsPage(store: store)));
      await tester.pumpAndSettle();

      final week = tester.getSemantics(find.bySemanticsLabel('Week'));
      expect(week.flagsCollection.isSelected, Tristate.isTrue);
      final day = tester.getSemantics(find.bySemanticsLabel('Day'));
      expect(day.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('the shell tabs', (tester) async {
      await ready(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Today'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Limits'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      handle.dispose();
    });
  });
}
