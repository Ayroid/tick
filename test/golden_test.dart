import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tick/clock.dart';
import 'package:tick/home.dart';
import 'package:tick/insights_screen.dart';
import 'package:tick/limits_screen.dart';
import 'package:tick/onboarding.dart';
import 'package:tick/store.dart';
import 'package:tick/theme.dart';

import 'fake_phone.dart';

const minute = 60000;

/// Goldens render with the real typefaces.
///
/// Three families, and all three matter: without the sans every string draws
/// in the runner's fallback, without Lucide every icon is a hollow box, and
/// without a mono every duration and date is one too — which is most of the
/// numbers on every screen.
Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }

  await load('PlusJakartaSans', 'assets/fonts/PlusJakartaSans.ttf');

  // Lucide ships its font inside the package, so this path is as reproducible
  // as the dependency itself. IconData carries fontPackage, so the family
  // Flutter actually looks up is package-qualified.
  const lucide = 'hosted/pub.dev/lucide_icons_flutter-3.1.17/assets/lucide.ttf';
  for (final candidate in [
    '${Platform.environment['HOME']}/.pub-cache/$lucide',
    '${Platform.environment['PUB_CACHE']}/$lucide',
  ]) {
    if (File(candidate).existsSync()) {
      await load('packages/lucide_icons_flutter/Lucide', candidate);
      break;
    }
  }

  // The app asks for the *platform* mono by design — nothing is bundled — so
  // a golden run has to supply one. Whichever the machine has; best-effort
  // rather than pinned, exactly as in Wick and Penny.
  for (final candidate in [
    '/usr/share/fonts/google-noto-vf/NotoSansMono[wght].ttf',
    '/usr/share/fonts/adwaita-mono-fonts/AdwaitaMono-Regular.ttf',
    '/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf',
    '/System/Library/Fonts/Menlo.ttc',
  ]) {
    if (File(candidate).existsSync()) {
      await load('monospace', candidate);
      break;
    }
  }
}

/// Let the mascot PNGs actually decode.
///
/// Under fake async an `Image.asset` never resolves, so every pose renders as
/// its fallback and the goldens quietly record the drawn mark instead of the
/// art. `precacheImage` does not help: `cacheHeight` wraps the provider in a
/// `ResizeImage` with a different cache key, so the precached one is never the
/// one looked up. Real elapsed time is the only thing that works.
Future<void> settleImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pumpAndSettle();
}

/// Mid-month, mid-morning on a Thursday. Every screen renders a date or a
/// greeting, so without a pinned clock these images fail the next day.
final _pinned = DateTime(2026, 9, 17, 10, 30);

/// A week with something real on every surface.
const _history = {
  '2026-09-17': {
    'com.social': 42 * minute,
    'com.mail': 8 * minute,
    'com.news': 21 * minute,
  },
  '2026-09-16': {'com.social': 96 * minute, 'com.mail': 22 * minute},
  '2026-09-15': {'com.social': 61 * minute, 'com.news': 14 * minute},
  '2026-09-14': {'com.social': 130 * minute},
};

Future<TickStore> seeded({bool withRules = true}) async {
  final store = TickStore();
  await store.load();
  if (withRules) {
    store.setLimit('com.social', 60);
    store.setLimit('com.news', 30);
    store.saveSchedule(
      Schedule(
        id: 'bedtime',
        name: 'Bedtime',
        packages: {'com.social', 'com.news'},
        days: const [],
        from: '22:00',
        to: '07:00',
      ),
    );
  }
  return store;
}

/// Pump one screen at a phone size and file it against its golden.
Future<void> shot(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  TickStore? store,
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2280)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(dark: dark),
      home: store == null
          ? build()
          : ListenableBuilder(listenable: store, builder: (_, _) => build()),
    ),
  );
  await tester.pumpAndSettle();
  await settleImages(tester);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  setUpAll(loadFonts);

  late DateTime Function() previousClock;

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    previousClock = useFixedClock(_pinned);
    mockNative(usage: _history);
  });

  tearDown(() {
    clock = previousClock;
    unmockNative();
  });

  testWidgets('today', (tester) async {
    final store = await seeded();
    await shot(
      tester,
      'today',
      () => HomePage(store: store, onSettings: () {}),
      store: store,
    );
  });

  testWidgets('today dark', (tester) async {
    final store = await seeded();
    await shot(
      tester,
      'today_dark',
      () => HomePage(store: store, onSettings: () {}),
      store: store,
      dark: true,
    );
  });

  testWidgets('today with nothing on it', (tester) async {
    mockNative();
    final store = await seeded(withRules: false);
    await shot(
      tester,
      'today_empty',
      () => HomePage(store: store, onSettings: () {}),
      store: store,
    );
  });

  testWidgets('limits', (tester) async {
    final store = await seeded();
    await shot(tester, 'limits', () => LimitsPage(store: store), store: store);
  });

  testWidgets('limits dark', (tester) async {
    final store = await seeded();
    await shot(
      tester,
      'limits_dark',
      () => LimitsPage(store: store),
      store: store,
      dark: true,
    );
  });

  testWidgets('limits before anything is limited', (tester) async {
    final store = await seeded(withRules: false);
    await shot(
      tester,
      'limits_empty',
      () => LimitsPage(store: store),
      store: store,
    );
  });

  testWidgets('insights', (tester) async {
    final store = await seeded();
    await shot(
      tester,
      'insights',
      () => InsightsPage(store: store),
      store: store,
    );
  });

  testWidgets('insights dark', (tester) async {
    final store = await seeded();
    await shot(
      tester,
      'insights_dark',
      () => InsightsPage(store: store),
      store: store,
      dark: true,
    );
  });

  testWidgets('the permission gate', (tester) async {
    mockNative(usageGranted: false);
    final store = await seeded(withRules: false);
    await shot(
      tester,
      'gate',
      () => HomePage(store: store, onSettings: () {}),
      store: store,
    );
  });

  testWidgets('onboarding', (tester) async {
    final store = await seeded(withRules: false);
    await shot(
      tester,
      'onboarding',
      () => OnboardingScreen(store: store),
      store: store,
    );
  });

  testWidgets('the limit sheet', (tester) async {
    final store = await seeded();
    tester.view
      ..physicalSize = const Size(1080, 2280)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(dark: false),
        home: ListenableBuilder(
          listenable: store,
          builder: (_, _) => LimitsPage(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settleImages(tester);
    await tester.tap(find.text('Social'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/limit_sheet.png'),
    );
  });
}
