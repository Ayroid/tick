/// The only place a span of milliseconds becomes a string.
///
/// Everything upstream — the store, the archive, the channel — carries integer
/// milliseconds, which is what `UsageStatsManager` hands back. Formatting in
/// one place is what stops `1h 24m` on one screen and `84 min` on the next.
library;

/// `1h 24m` · `24m` · `<1m` · `0m`.
///
/// Seconds are never shown. Nobody has ever wanted to know they spent four
/// minutes and eleven seconds in a messaging app, and a number that changes
/// while you look at it reads as broken rather than live. Anything under a
/// minute but above zero is `<1m` — visited, but not really used.
String humanMs(int ms) {
  if (ms <= 0) return '0m';
  final minutes = ms ~/ 60000;
  if (minutes == 0) return '<1m';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// The same span with room for one label on a chart axis: `2h` · `45m` · `0`.
///
/// Rounds to the nearest hour above two hours, because an axis tick that reads
/// `2h 37m` is not a tick, it is a sentence.
String shortMs(int ms) {
  if (ms <= 0) return '0';
  final minutes = ms ~/ 60000;
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes}m';
  final hours = (minutes / 60).round();
  return '${hours < 1 ? 1 : hours}h';
}

/// `30m` · `2h` · `1h 30m` — a limit, which is always a whole number of
/// minutes because that is what the picker offers.
String humanMinutes(int minutes) => humanMs(minutes * 60000);

/// `4 of 30m used` reads better than two durations jammed together, and the
/// remaining half is what a person is actually asking. Negative is clamped:
/// going over a limit leaves zero left, not minus eleven.
String remainingMs(int usedMs, int limitMinutes) =>
    humanMs((limitMinutes * 60000 - usedMs).clamp(0, 1 << 62));
