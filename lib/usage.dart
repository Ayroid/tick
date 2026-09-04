/// The channel to the parts of Android that Dart cannot see.
///
/// Everything here is a call and a cast; no decisions are made in this file.
/// It is kept widget-free and static so a test can stub the channel with
/// `setMockMethodCallHandler` and never need a device — which is what makes
/// the rest of the app testable at all.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.ayroid.tick/native');

/// What has and has not been granted. Read fresh every time the app resumes:
/// all three are toggles in Settings that the user can flip while Tick is in
/// the background, and a cached answer would have the app claiming to enforce
/// limits it is no longer able to enforce.
@immutable
class Grants {
  const Grants({
    this.usage = false,
    this.accessibility = false,
    this.notifications = false,
    this.postNotifications = false,
  });

  /// Usage access. Without it there is nothing to show at all.
  final bool usage;

  /// The guard. Without it limits are recorded but not enforced.
  final bool accessibility;

  /// The notification listener. Optional, and opt-in from Insights.
  final bool notifications;

  /// Ordinary notification permission, for the "time's up" message.
  final bool postNotifications;

  static Grants fromMap(Map<Object?, Object?> m) => Grants(
    usage: m['usage'] == true,
    accessibility: m['accessibility'] == true,
    notifications: m['notifications'] == true,
    postNotifications: m['postNotifications'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is Grants &&
      other.usage == usage &&
      other.accessibility == accessibility &&
      other.notifications == notifications &&
      other.postNotifications == postNotifications;

  @override
  int get hashCode =>
      Object.hash(usage, accessibility, notifications, postNotifications);
}

/// An installed app, as the launcher knows it.
@immutable
class AppInfo {
  const AppInfo(this.package, this.label, this.icon);

  final String package;
  final String label;

  /// PNG bytes at 96px. Held in memory for the session and never persisted —
  /// they belong to the phone, not to Tick's backup.
  final Uint8List? icon;
}

/// One app's slice of a window of time.
@immutable
class AppUsage {
  const AppUsage(this.package, this.ms, this.opens);

  final String package;
  final int ms;
  final int opens;
}

/// Usage over a span, as the system recorded it.
@immutable
class UsageWindow {
  const UsageWindow({
    required this.granted,
    this.byPackage = const {},
    this.unlocks = 0,
  });

  /// False means usage access has not been granted — an ordinary state with a
  /// permission card for it, not an error.
  final bool granted;
  final Map<String, AppUsage> byPackage;
  final int unlocks;

  static const denied = UsageWindow(granted: false);

  int get totalMs => byPackage.values.fold(0, (sum, app) => sum + app.ms);

  int get totalOpens => byPackage.values.fold(0, (sum, app) => sum + app.opens);

  /// Only the packages a person would call apps.
  ///
  /// The event stream also carries the home screen and the system surfaces you
  /// pass through — the package installer, the permission controller, the
  /// intent resolver. On one real day the launcher alone was the second
  /// heaviest row at 1h11 across 363 opens, and the package installer showed
  /// 105 opens. None of them appear in Digital Wellbeing, and a screen-time
  /// app whose top result is the home screen is answering a question nobody
  /// asked.
  ///
  /// An empty [known] means the catalogue has not loaded yet, and filtering
  /// against it would blank the screen — so it is left alone.
  UsageWindow onlyApps(Iterable<String> known) {
    if (byPackage.isEmpty) return this;
    final keep = known.toSet();
    if (keep.isEmpty) return this;
    return UsageWindow(
      granted: granted,
      unlocks: unlocks,
      byPackage: {
        for (final e in byPackage.entries)
          if (keep.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// Longest first — the order every screen wants.
  List<AppUsage> get ranked {
    final list = byPackage.values.toList();
    list.sort((a, b) => b.ms.compareTo(a.ms));
    return list;
  }
}

class Native {
  const Native._();

  static Future<Grants> grants() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'permissions',
    );
    return result == null ? const Grants() : Grants.fromMap(result);
  }

  /// Foreground time between two instants.
  ///
  /// The range is passed as epoch milliseconds rather than as a number of days
  /// back, so the caller owns what "a day" means. Day boundaries are local
  /// midnights computed with the `DateTime` constructor — see `store.dart`.
  static Future<UsageWindow> usage(DateTime from, DateTime to) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('usage', {
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
    });
    if (result == null || result['granted'] != true) return UsageWindow.denied;

    final raw = (result['byPackage'] as Map<Object?, Object?>?) ?? const {};
    return UsageWindow(
      granted: true,
      unlocks: (result['unlocks'] as num?)?.toInt() ?? 0,
      byPackage: {
        for (final entry in raw.entries)
          entry.key as String: AppUsage(
            entry.key as String,
            ((entry.value as Map)['ms'] as num?)?.toInt() ?? 0,
            ((entry.value as Map)['opens'] as num?)?.toInt() ?? 0,
          ),
      },
    );
  }

  /// Every app with a launcher icon. Asked for once per session — it is a few
  /// hundred KB of icon bytes and the list does not change while you look at
  /// it.
  static Future<Map<String, AppInfo>> apps() async {
    final result = await _channel.invokeMethod<List<Object?>>('apps');
    if (result == null) return const {};
    final apps = <String, AppInfo>{};
    for (final entry in result) {
      final map = entry as Map<Object?, Object?>;
      final package = map['package'] as String?;
      if (package == null) continue;
      apps[package] = AppInfo(
        package,
        map['label'] as String? ?? package,
        map['icon'] as Uint8List?,
      );
    }
    return apps;
  }

  /// Mirror the rules to the guard, which reads them without a Flutter engine.
  static Future<void> setRules(String json) =>
      _channel.invokeMethod<void>('setRules', json);

  /// `{ 'YYYY-MM-DD': { package: count } }`, or empty if the listener has
  /// never been switched on.
  static Future<Map<String, Map<String, int>>> notifications() async {
    final raw = await _channel.invokeMethod<String>('notifications');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final day in decoded.entries)
          day.key: {
            for (final app in (day.value as Map<String, dynamic>).entries)
              app.key: (app.value as num).toInt(),
          },
      };
    } catch (e) {
      debugPrint('notifications: could not read counts ($e)');
      return const {};
    }
  }

  /// Each of these opens a Settings screen. They return false on the vendor
  /// ROMs that ship without one, so the caller can say so rather than leaving
  /// the user tapping a button that does nothing.
  static Future<bool> openUsageSettings() async =>
      await _channel.invokeMethod<bool>('openUsageSettings') ?? false;

  static Future<bool> openAccessibilitySettings() async =>
      await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;

  static Future<bool> openNotificationSettings() async =>
      await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
}
