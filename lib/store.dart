import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'clock.dart';
import 'usage.dart';

// ── Days ────────────────────────────────────────────────────────────────────
// Zero-padded so lexical order is chronological — the archive is a map keyed
// by these and is sorted as strings.

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Day arithmetic goes through the constructor, never a `Duration`. A Duration
/// is 24 real hours, and on the two days a year the clocks move that lands on
/// the wrong calendar day — which would silently shift a whole week of usage
/// into the wrong bucket.
DateTime shiftDays(DateTime d, int by) => DateTime(d.year, d.month, d.day + by);

DateTime startOfWeek(DateTime d) => shiftDays(d, -(d.weekday - 1));

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime today() {
  final now = clock();
  return DateTime(now.year, now.month, now.day);
}

/// The instant after [day] ends. Used as the exclusive end of a usage window.
DateTime endOfDay(DateTime day) => shiftDays(day, 1);

int _lastId = 0;

String newId() {
  var t = DateTime.now().microsecondsSinceEpoch;
  if (t <= _lastId) t = _lastId + 1;
  _lastId = t;
  return t.toString();
}

// ── Model ───────────────────────────────────────────────────────────────────

/// A window in which a set of apps is blocked regardless of how long they have
/// been used. Bedtime, work hours, a weekend rule.
@immutable
class Schedule {
  const Schedule({
    required this.id,
    required this.name,
    required this.packages,
    required this.days,
    required this.from,
    required this.to,
    this.enabled = true,
  });

  final String id;
  final String name;
  final Set<String> packages;

  /// 1 = Monday .. 7 = Sunday, matching `DateTime.weekday`. Empty means every
  /// day, which is also what the native side assumes.
  final List<int> days;

  /// `HH:mm`, local. A [to] earlier than [from] wraps midnight — 22:00 to
  /// 07:00 is the common case, not the edge one.
  final String from;
  final String to;
  final bool enabled;

  Schedule copyWith({
    String? name,
    Set<String>? packages,
    List<int>? days,
    String? from,
    String? to,
    bool? enabled,
  }) => Schedule(
    id: id,
    name: name ?? this.name,
    packages: packages ?? this.packages,
    days: days ?? this.days,
    from: from ?? this.from,
    to: to ?? this.to,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'packages': packages.toList(),
    'days': days,
    'from': from,
    'to': to,
    'enabled': enabled,
  };

  /// Every read is defensive and clamped. There is no version chain in this
  /// app: a stored blob is a hand-editable JSON export, and a field that has
  /// gone missing or arrived as the wrong type must degrade rather than throw.
  static Schedule fromJson(Map<String, dynamic> j) => Schedule(
    id: j['id'] as String? ?? newId(),
    name: j['name'] as String? ?? 'Schedule',
    packages: {...?(j['packages'] as List?)?.whereType<String>()},
    days: [
      ...?(j['days'] as List?)?.whereType<num>().map(
        (d) => d.toInt().clamp(1, 7),
      ),
    ],
    from: _time(j['from']),
    to: _time(j['to']),
    enabled: j['enabled'] as bool? ?? true,
  );

  static String _time(Object? raw) {
    if (raw is! String) return '00:00';
    final parts = raw.split(':');
    if (parts.length != 2) return '00:00';
    final h = int.tryParse(parts[0])?.clamp(0, 23) ?? 0;
    final m = int.tryParse(parts[1])?.clamp(0, 59) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Whether this schedule covers [at]. Mirrors `Rules.activeNow` in Kotlin —
  /// the guard enforces, this tells the screen what the guard will do.
  ///
  /// When the window wraps midnight, the half after midnight belongs to the
  /// *previous* day's occurrence: a Friday bedtime still ends at 07:00 on
  /// Saturday morning.
  bool activeAt(DateTime at) {
    if (!enabled) return false;
    final f = _minutes(from), t = _minutes(to);
    if (f == t) return false;
    final now = at.hour * 60 + at.minute;
    final yesterday = at.weekday == 1 ? 7 : at.weekday - 1;
    if (f < t) return now >= f && now < t && _onDay(at.weekday);
    return (now >= f && _onDay(at.weekday)) || (now < t && _onDay(yesterday));
  }

  bool _onDay(int weekday) => days.isEmpty || days.contains(weekday);

  static int _minutes(String time) {
    final parts = time.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}

/// A focus session: these apps, blocked until this instant, then gone.
///
/// Not a schedule with a one-off date, because it has no shape a schedule has
/// — no days, no recurrence, and it deletes itself. A stored `until` in the
/// past simply is not a session.
@immutable
class FocusSession {
  const FocusSession({required this.until, required this.packages});

  static const none = FocusSession(until: null, packages: <String>{});

  final DateTime? until;
  final Set<String> packages;

  bool get active =>
      until != null && until!.isAfter(clock()) && packages.isNotEmpty;

  Duration get left {
    final end = until;
    if (end == null) return Duration.zero;
    final remaining = end.difference(clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Map<String, dynamic> toJson() => {
    'until': until?.millisecondsSinceEpoch ?? 0,
    'packages': packages.toList(),
  };

  static FocusSession fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    final ms = (j['until'] as num?)?.toInt() ?? 0;
    return FocusSession(
      until: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
      packages: {...?(j['packages'] as List?)?.whereType<String>()},
    );
  }
}

// ── Store ───────────────────────────────────────────────────────────────────

const _rulesKey = 'rules';
const _archiveKey = 'archive';
const _themeKey = 'themeMode';
const _onboardedKey = 'onboarded';
const _archivedKey = 'lastArchived';

/// A day under this is not worth a row in the archive. Below a minute an app
/// was glanced at, not used, and keeping every one of them would triple the
/// blob for information nobody reads.
const _archiveFloor = 60 * 1000;

/// How far back a catch-up will look. `queryEvents` keeps roughly a week on
/// most devices and nothing at all beyond it, so asking for more is a channel
/// round trip that returns an empty map.
const _catchUpDays = 10;

/// Everything Tick knows, and the only thing it persists.
///
/// Note what is *not* here: screen time. The system has recorded it since the
/// phone was first switched on, and a second copy kept by this app would only
/// ever be a less accurate one that stops when we are killed. [archive] is the
/// single exception — a daily total kept once the raw events have aged out.
class TickStore extends ChangeNotifier {
  /// package -> minutes a day.
  final Map<String, int> limits = {};
  final List<Schedule> schedules = [];
  FocusSession focus = FocusSession.none;

  /// `'YYYY-MM-DD' -> package -> ms`, for days the system no longer has
  /// events for. Today is never in here; today comes live.
  final Map<String, Map<String, int>> archive = {};

  ThemeMode themeMode = ThemeMode.light;
  bool onboarded = false;
  String lastArchived = '';

  // Live. Re-read on every resume, never persisted.
  bool loaded = false;
  Grants grants = const Grants();
  Map<String, AppInfo> apps = const {};
  UsageWindow todayUsage = UsageWindow.denied;
  Map<String, Map<String, int>> notifications = const {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode
        .values[(prefs.getInt(_themeKey) ?? ThemeMode.light.index).clamp(0, 2)];
    onboarded = prefs.getBool(_onboardedKey) ?? false;
    lastArchived = prefs.getString(_archivedKey) ?? '';

    final rules = prefs.getString(_rulesKey);
    if (rules != null) {
      try {
        _adoptRules(_decodeRules(rules));
      } catch (e) {
        // A bad blob starts empty rather than bricking launch, and the stored
        // string is left untouched so it is still recoverable by hand.
        debugPrint('rules: could not read stored data ($e)');
      }
    }

    final stored = prefs.getString(_archiveKey);
    if (stored != null) {
      try {
        _adoptArchive(_decodeArchive(stored));
      } catch (e) {
        debugPrint('archive: could not read stored data ($e)');
      }
    }

    loaded = true;
    notifyListeners();
    await refresh();
  }

  /// Re-read everything that belongs to the system: what has been granted,
  /// what has been installed, and today's usage so far.
  ///
  /// Called on load and on every resume. All three can change while Tick is in
  /// the background — a permission revoked in Settings, an app uninstalled,
  /// and today's usage constantly — so none of them is ever cached across a
  /// trip to another app.
  Future<void> refresh() async {
    try {
      grants = await Native.grants();
      if (!grants.usage) {
        todayUsage = UsageWindow.denied;
        notifyListeners();
        return;
      }
      if (apps.isEmpty) apps = await Native.apps();
      final start = today();
      todayUsage = (await Native.usage(start, clock())).onlyApps(apps.keys);
      if (grants.notifications) notifications = await Native.notifications();
      await _catchUpArchive();
    } catch (e) {
      // A channel that is not there at all — a widget test, a desktop build —
      // leaves the screens on their permission cards rather than crashing.
      debugPrint('refresh: native side unavailable ($e)');
    }
    notifyListeners();
  }

  /// Fold every completed day since the last catch-up into [archive].
  ///
  /// The raw event stream only goes back about a week, so a total that is not
  /// captured within that window is gone for good. Today is deliberately
  /// excluded — it is not finished, and reading it live is both cheaper and
  /// always right.
  Future<void> _catchUpArchive() async {
    final yesterday = shiftDays(today(), -1);
    final from = lastArchived.isEmpty
        ? shiftDays(yesterday, -_catchUpDays)
        : shiftDays(parseDay(lastArchived), 1);

    var day = from.isBefore(shiftDays(yesterday, -_catchUpDays))
        ? shiftDays(yesterday, -_catchUpDays)
        : from;
    var wrote = false;

    while (!day.isAfter(yesterday)) {
      final window = (await Native.usage(
        day,
        endOfDay(day),
      )).onlyApps(apps.keys);
      if (window.granted) {
        final totals = {
          for (final app in window.byPackage.values)
            if (app.ms >= _archiveFloor) app.package: app.ms,
        };
        if (totals.isNotEmpty) archive[dayKey(day)] = totals;
        lastArchived = dayKey(day);
        wrote = true;
      }
      day = shiftDays(day, 1);
    }

    if (wrote) {
      _prune();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_archiveKey, jsonEncode(archive));
      await prefs.setString(_archivedKey, lastArchived);
    }
  }

  /// Keep a bit over a year. Nothing in the app reads further back, and the
  /// whole map is re-encoded on every write.
  void _prune() {
    if (archive.length <= 400) return;
    final keys = archive.keys.toList()..sort();
    for (final old in keys.take(archive.length - 400)) {
      archive.remove(old);
    }
  }

  // ── Reading ───────────────────────────────────────────────────────────────

  /// Milliseconds [package] has been in front today. Live, from the system.
  int usedTodayMs(String package) => todayUsage.byPackage[package]?.ms ?? 0;

  /// The name a person recognises. Falls back to the package id: an app can be
  /// uninstalled while its usage stays in the archive, and a row that reads
  /// `com.example.thing` is better than a row that vanished.
  String labelOf(String package) => apps[package]?.label ?? package;

  /// Why [package] is blocked right now, or null if it is not.
  ///
  /// The guard decides this for real, in Kotlin. This is the same arithmetic
  /// so a screen can say what will happen without waiting to be kicked out of
  /// something to find out.
  String? blockReason(String package) {
    if (focus.active && focus.packages.contains(package)) {
      return 'Focus session';
    }
    final now = clock();
    for (final schedule in schedules) {
      if (schedule.packages.contains(package) && schedule.activeAt(now)) {
        return schedule.name;
      }
    }
    final limit = limits[package];
    if (limit != null && usedTodayMs(package) >= limit * 60000) {
      return 'Daily limit';
    }
    return null;
  }

  /// Apps with a limit, over budget first, then by how much of it is spent.
  /// An app you are about to run out of is the one you came to look at.
  List<String> get limitedPackages {
    final list = limits.keys.toList();
    list.sort((a, b) {
      final ra = usedTodayMs(a) / (limits[a]! * 60000).clamp(1, 1 << 40);
      final rb = usedTodayMs(b) / (limits[b]! * 60000).clamp(1, 1 << 40);
      return rb.compareTo(ra);
    });
    return list;
  }

  // ── Writing ───────────────────────────────────────────────────────────────

  /// A null or zero [minutes] removes the limit. Limits are freely editable,
  /// including while an app is blocked by one: it is the user's phone, and a
  /// lock they cannot open is a lock on the wrong person.
  void setLimit(String package, int? minutes) {
    if (minutes == null || minutes <= 0) {
      limits.remove(package);
    } else {
      limits[package] = minutes;
    }
    _commit();
  }

  void saveSchedule(Schedule schedule) {
    final at = schedules.indexWhere((s) => s.id == schedule.id);
    if (at >= 0) {
      schedules[at] = schedule;
    } else {
      schedules.add(schedule);
    }
    _commit();
  }

  void removeSchedule(String id) {
    schedules.removeWhere((s) => s.id == id);
    _commit();
  }

  void startFocus(Duration length, Set<String> packages) {
    focus = FocusSession(until: clock().add(length), packages: packages);
    _commit();
  }

  void endFocus() {
    focus = FocusSession.none;
    _commit();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  /// Every rules mutation lands in two places: shared_preferences for the next
  /// launch, and the native prefs file for the guard, which has to decide
  /// whether to block an app at a moment when there is usually no Flutter
  /// engine alive to ask. Dart is the only writer; the guard only ever reads.
  void _commit() {
    notifyListeners();
    final json = jsonEncode(_rulesJson());
    // Fire-and-forget: the UI never waits on disk.
    SharedPreferences.getInstance().then((p) => p.setString(_rulesKey, json));
    Native.setRules(json).catchError((Object e) {
      debugPrint('setRules: guard not reachable ($e)');
    });
  }

  Map<String, dynamic> _rulesJson() => {
    'limits': limits,
    'schedules': [for (final s in schedules) s.toJson()],
    'focus': focus.toJson(),
  };

  // ── Backup ────────────────────────────────────────────────────────────────

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'exportedAt': clock().toIso8601String(),
    'rules': _rulesJson(),
    'archive': archive,
  });

  /// True if the file was read. Nothing is cleared until decoding has returned
  /// successfully, so a malformed import leaves the existing data exactly as
  /// it was — the caller only has to tell the user it failed.
  bool importJson(String raw) {
    try {
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      final rules = _decodeRules(jsonEncode(doc['rules'] ?? doc));
      final days = _decodeArchive(jsonEncode(doc['archive'] ?? {}));
      _adoptRules(rules);
      _adoptArchive(days);
      _commit();
      SharedPreferences.getInstance().then(
        (p) => p.setString(_archiveKey, jsonEncode(archive)),
      );
      return true;
    } catch (e) {
      debugPrint('import: rejected ($e)');
      return false;
    }
  }

  /// Pure, and throws. Keeping decode separate from adopt is the whole reason
  /// a bad import cannot leave the store half-replaced.
  static ({
    Map<String, int> limits,
    List<Schedule> schedules,
    FocusSession focus,
  })
  _decodeRules(String raw) {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    return (
      limits: {
        for (final e in (doc['limits'] as Map<String, dynamic>? ?? {}).entries)
          if ((e.value as num?) != null)
            e.key: (e.value as num).toInt().clamp(1, 24 * 60),
      },
      schedules: [
        for (final s in (doc['schedules'] as List? ?? const []))
          Schedule.fromJson(s as Map<String, dynamic>),
      ],
      focus: FocusSession.fromJson(doc['focus'] as Map<String, dynamic>?),
    );
  }

  static Map<String, Map<String, int>> _decodeArchive(String raw) {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final day in doc.entries)
        if (day.value is Map)
          day.key: {
            for (final app in (day.value as Map<String, dynamic>).entries)
              if (app.value is num)
                app.key: (app.value as num).toInt().clamp(0, 1 << 40),
          },
    };
  }

  void _adoptRules(
    ({Map<String, int> limits, List<Schedule> schedules, FocusSession focus})
    doc,
  ) {
    limits
      ..clear()
      ..addAll(doc.limits);
    schedules
      ..clear()
      ..addAll(doc.schedules);
    focus = doc.focus;
  }

  void _adoptArchive(Map<String, Map<String, int>> days) {
    archive
      ..clear()
      ..addAll(days);
    _prune();
  }
}
