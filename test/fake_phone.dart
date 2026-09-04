import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick/store.dart';
import 'package:tick/theme.dart';

/// A phone, as far as Tick is concerned.
///
/// Every screen in this app reads the system through one method channel, so
/// stubbing that channel is the whole of what a test needs — no device, no
/// emulator, no usage access. This lives in its own file rather than being
/// copied per test the way the sibling apps do theirs: it is forty lines of
/// fixture rather than five, and three divergent copies of a fake phone would
/// be three different phones.
const channel = MethodChannel('com.ayroid.tick/native');

/// Every call the app made down the channel, in order.
final calls = <MethodCall>[];

/// [usage] is keyed by day then package, in milliseconds. A day not listed has
/// no records — which is also what a real device returns for a day that has
/// aged out of the event stream.
void mockNative({
  bool usageGranted = true,
  bool accessibility = true,
  bool notificationAccess = false,
  Map<String, Map<String, int>> usage = const {},
  Map<String, Map<String, int>> notifications = const {},
  Map<String, String> apps = const {
    'com.social': 'Social',
    'com.mail': 'Mail',
    'com.news': 'News',
  },
}) {
  calls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'permissions':
            return {
              'usage': usageGranted,
              'accessibility': accessibility,
              'notifications': notificationAccess,
              'postNotifications': true,
            };
          case 'apps':
            return [
              for (final app in apps.entries)
                // No icon bytes: decoding a real PNG under fake async is a
                // fight the tests do not need, and AppIcon's fallback is the
                // initial on a tinted square, which renders synchronously.
                {'package': app.key, 'label': app.value, 'icon': null},
            ];
          case 'usage':
            if (!usageGranted) return {'granted': false};
            final start = DateTime.fromMillisecondsSinceEpoch(
              call.arguments['start'] as int,
            );
            final day = usage[dayKey(start)] ?? const {};
            return {
              'granted': true,
              'unlocks': day.isEmpty ? 0 : 7,
              'byPackage': {
                for (final e in day.entries) e.key: {'ms': e.value, 'opens': 3},
              },
            };
          case 'notifications':
            return _encode(notifications);
          default:
            return null;
        }
      });
}

String _encode(Map<String, Map<String, int>> days) {
  final parts = [
    for (final day in days.entries)
      '"${day.key}":{${day.value.entries.map((a) => '"${a.key}":${a.value}').join(',')}}',
  ];
  return '{${parts.join(',')}}';
}

void unmockNative() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

/// A phone-shaped window.
///
/// The default 800x600 test window puts a sheet's primary button below the
/// fold, and lays the tab pill out at a width no phone has.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// One screen under the real theme, without the shell around it.
Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: appTheme(dark: dark),
  debugShowCheckedModeBanner: false,
  home: child,
);

/// A screen inside the same ListenableBuilder the shell gives it.
///
/// Pumping a page bare means it never rebuilds when something is changed
/// through a sheet, and half the flows in this app end in a sheet.
Widget page(TickStore store, Widget Function() build, {bool dark = false}) =>
    wrap(
      ListenableBuilder(listenable: store, builder: (_, _) => build()),
      dark: dark,
    );
