import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tick/clock.dart';
import 'package:tick/home.dart';
import 'package:tick/insights_screen.dart';
import 'package:tick/limits_screen.dart';
import 'package:tick/main.dart';
import 'package:tick/onboarding.dart';
import 'package:tick/store.dart';

import 'fake_phone.dart';

const minute = 60000;

Future<TickStore> loaded(WidgetTester tester) async {
  final store = TickStore();
  await store.load();
  await tester.pump();
  return store;
}

void main() {
  late DateTime Function() previousClock;

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    previousClock = useFixedClock(DateTime(2026, 9, 17, 10, 30));
    mockNative(
      usage: {
        '2026-09-17': {'com.social': 42 * minute, 'com.mail': 8 * minute},
        '2026-09-16': {'com.social': 90 * minute},
      },
    );
  });

  tearDown(() {
    clock = previousClock;
    unmockNative();
  });

  group('Today', () {
    testWidgets('shows the day\'s total and the apps behind it', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('50m'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);
      expect(find.text('42m'), findsOneWidget);
      expect(find.text('Mail'), findsOneWidget);
      expect(find.text('8m'), findsOneWidget);
    });

    testWidgets('says nothing yet rather than showing an empty chart', (
      tester,
    ) async {
      phone(tester);
      mockNative();
      final store = await loaded(tester);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing yet today'), findsOneWidget);
      expect(find.text('0m'), findsOneWidget);
    });

    testWidgets('without usage access it asks for it and shows nothing else', (
      tester,
    ) async {
      phone(tester);
      mockNative(usageGranted: false);
      final store = await loaded(tester);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tick needs to see your screen time'), findsOneWidget);
      expect(find.text('Social'), findsNothing);
    });

    testWidgets('a limit shows what is left of it, in the row', (tester) async {
      phone(tester);
      final store = await loaded(tester);
      store.setLimit('com.social', 60);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('18m left of 1h'), findsOneWidget);
      // The ring names its own numbers rather than a percentage of something
      // the reader has to reconstruct.
      expect(find.text('42m of 1h limited'), findsOneWidget);
    });

    testWidgets('a spent limit reads as done, never as a failure', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      store.setLimit('com.social', 30);
      await tester.pumpWidget(
        page(store, () => HomePage(store: store, onSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily limit · done for today'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('Limits', () {
    testWidgets('starts empty, and offers the one thing to do', (tester) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();

      expect(find.text('No limits yet'), findsOneWidget);
      expect(find.text('Nothing is limited yet'), findsOneWidget);
    });

    testWidgets('a limit can be set end to end, through the sheet', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add a limit'));
      await tester.pumpAndSettle();
      expect(find.text('Which app?'), findsOneWidget);

      await tester.tap(find.text('Social'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45m'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save limit'));
      await tester.pumpAndSettle();

      expect(store.limits, {'com.social': 45});
      expect(find.text('1 app limited'), findsOneWidget);
      expect(find.text('3m left of 45m'), findsOneWidget);
    });

    testWidgets('a limit can be raised while it is blocking', (tester) async {
      phone(tester);
      final store = await loaded(tester);
      store.setLimit('com.social', 30);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Done for today'), findsOneWidget);

      await tester.tap(find.text('Social'));
      await tester.pumpAndSettle();
      // The sheet says so rather than pretending the change is free.
      expect(
        find.textContaining('It will block until midnight.'),
        findsOneWidget,
      );

      await tester.tap(find.text('1h'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save limit'));
      await tester.pumpAndSettle();

      expect(store.limits, {'com.social': 60});
      expect(find.text('18m left of 1h'), findsOneWidget);
    });

    testWidgets('the guard card appears only once there is a rule', (
      tester,
    ) async {
      phone(tester);
      mockNative(accessibility: false);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('Limits are not being enforced'), findsNothing);

      store.setLimit('com.social', 30);
      await tester.pumpAndSettle();
      expect(find.text('Limits are not being enforced'), findsOneWidget);
    });

    testWidgets('a focus session runs, counts down and can be ended', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      store.setLimit('com.social', 60);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Start a focus session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45m'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(store.focus.active, isTrue);
      expect(find.text('45m left · 1 app'), findsOneWidget);

      await tester.tap(find.text('End'));
      await tester.pumpAndSettle();
      expect(store.focus.active, isFalse);
    });

    testWidgets('a schedule is created and reads back as written', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      store.setLimit('com.social', 60);
      await tester.pumpWidget(page(store, () => LimitsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add a schedule'));
      await tester.pumpAndSettle();
      // 22:00 to 07:00 is the default, and it wraps.
      expect(
        find.text('Overnight — this runs until 07:00 the next morning.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Mail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save schedule'));
      await tester.pumpAndSettle();

      expect(store.schedules.single.packages, {'com.mail'});
      expect(find.text('22:00–07:00 · Every day · 1 app'), findsOneWidget);
      // 10:30 is not inside 22:00–07:00. The card reads the injectable clock,
      // so this is a real assertion rather than one that passes overnight.
      expect(find.text('On now'), findsNothing);
    });
  });

  group('Insights', () {
    testWidgets('rolls the week up and names the span', (tester) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => InsightsPage(store: store)));
      await tester.pumpAndSettle();

      // 90 minutes on the 16th plus 50 today.
      expect(find.text('2h 20m'), findsOneWidget);
      expect(find.text('Sep 14, 2026 – Sep 20, 2026'), findsOneWidget);
      expect(find.text('By app'), findsOneWidget);
    });

    testWidgets('the period switch changes the window', (tester) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => InsightsPage(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('50m'), findsOneWidget);
      expect(find.text('Thursday, September 17'), findsOneWidget);
    });

    testWidgets('notification counting is offered until it is on', (
      tester,
    ) async {
      phone(tester);
      final store = await loaded(tester);
      await tester.pumpWidget(page(store, () => InsightsPage(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('Count notifications too'), findsOneWidget);

      mockNative(
        notificationAccess: true,
        usage: {
          '2026-09-17': {'com.social': 42 * minute},
        },
        notifications: {
          '2026-09-17': {'com.social': 31},
        },
      );
      await store.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Count notifications too'), findsNothing);
      expect(find.text('31 notifications'), findsOneWidget);
    });
  });

  group('the app as a whole', () {
    testWidgets('leaves the launch frame once the store has loaded', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(const App());

      // The shell tuple is assigned in initState for exactly this reason: a
      // late initializer would first be read after loading finished, capture
      // the post-load values, and never fire a rebuild — leaving the app on
      // its launch frame forever.
      expect(find.byType(LaunchFrame), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(LaunchFrame), findsNothing);
      expect(find.byType(RootScreen), findsOneWidget);
    });

    testWidgets('a first run lands on onboarding, not the shell', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      phone(tester);
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Know your time'), findsOneWidget);
    });

    testWidgets('onboarding can be skipped straight into the app', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      phone(tester);
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(RootScreen), findsOneWidget);
    });

    testWidgets('the tabs move between the three pages', (tester) async {
      phone(tester);
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Limits'));
      await tester.pumpAndSettle();
      expect(find.text('Limits'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Insights'));
      await tester.pumpAndSettle();
      expect(find.text('By app'), findsOneWidget);
    });

    testWidgets('the theme switch repaints the whole app', (tester) async {
      phone(tester);
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      final light = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(light.themeMode, ThemeMode.light);

      final state = tester.state<State<App>>(find.byType(App));
      await (state as dynamic).store.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      final dark = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(dark.themeMode, ThemeMode.dark);
    });
  });
}
