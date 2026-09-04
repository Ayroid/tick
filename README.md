# Tick

Know your time. Take back control.

A screen-time app for Android. See where the day went, app by app, give the
ones that eat it a daily budget, and get sent back to the home screen when
that budget is gone.

- **Today.** The day's total, the apps behind it, unlocks and opens.
- **Daily limits.** A few minutes a day per app. Past that, Tick sends you
  home and says so. Editable at any time, including while an app is blocked —
  it is your phone.
- **Focus sessions.** Put a handful of apps away for the next 25 minutes. Ends
  on its own, leaves nothing behind.
- **Schedules.** Bedtime, working hours. They wrap midnight, which is the
  normal case rather than the edge one.
- **Day / week / month**, with a bar per day and a per-app breakdown.
- **Notification counts**, if you want them — optional, and off by default.
- **Local, quiet, no account.** No sign-in, no sync, no analytics. Your backup
  is a JSON file you export and keep.

## Build

```sh
flutter run                       # debug
flutter test                      # 132 unit, widget, a11y and golden tests
(cd android && ./gradlew :app:testDebugUnitTest)   # 11 Kotlin tests, no device
flutter test --update-goldens     # only when a pixel change is deliberate
flutter analyze
tool/release.sh                   # split-per-abi release APKs into releases/
```

Android only, and not by preference. iOS has no API that reports per-app usage
or reacts to an app being opened without Apple's Screen Time entitlement, so
half of this app cannot exist there.

## Installing it

Sideloading Tick trips two of Android's guards, both by design, and neither is
a defect in the build. An accessibility service is the single most abused
permission on Android, so a sideloaded app that declares one gets stopped
twice.

**1. Play Protect blocks the install** — *"App blocked to protect your device.
This app can request access to sensitive data."* That is the accessibility
service declaration being read off the manifest before anything runs. Tap
**More details → Install anyway**. If the dialog offers only *Got it*, turn the
scan off for the moment (Play Store → profile → Play Protect → settings →
*Scan apps with Play Protect*), install, and turn it back on.

**2. Enabling enforcement is a "restricted setting."** On Android 13 and later
the accessibility toggle for a sideloaded app is greyed out until you allow it
explicitly: **Settings → Apps → Tick → ⋮ → Allow restricted settings**. Then
the switch under Settings → Accessibility → Tick works. Usage access is not
restricted this way and can be granted straight from onboarding.

Without step 2 Tick still shows every number — it just records limits without
enforcing them, and the Limits screen says so rather than pretending.

## Layout

`lib/` is flat, one file per screen or sheet, plus five that cut across:

- **`store.dart`** is the model and the only thing that persists — one
  `ChangeNotifier`, rules and an archive in `shared_preferences`. Every screen
  listens.
- **`usage.dart`** is the method channel and nothing else: a call and a cast
  per method, no decisions. Stubbing it is the whole of what a test needs.
- **`theme.dart`** holds the palette and every shared shape (`TintCard`,
  `Segmented`, `TintChip`, `RoundIconButton`, `SoftCard`). If a widget is used
  twice it moves here.
- **`analytics.dart`** is the maths, kept widget-free so it is tested by
  calling it rather than by pumping a tree.
- **`duration.dart`** is the only place milliseconds become a string.

## Things that are settled

**Tick counts nothing.** Android's `UsageStatsManager` has recorded per-app
foreground time since the phone was first switched on. A second counter running
in our own process would only ever be a less accurate copy that stops when we
are killed. The one exception is `archive` — a daily total kept once the raw
events have aged out, because `queryEvents` only goes back about a week.

**Exactly one app is in front at a time, and `Usage.fold` is written that way.**
It tracks one current package and the instant it came forward, not a map of
open ones. Android fires `ACTIVITY_PAUSED` *and then* `ACTIVITY_STOPPED` for
the same activity, and a map-based version double-counted the second — a
launcher opened 345 times reported 5144 hours in one day. `fold` is a pure
function over plain data so the JVM tests can hold that shape down.

**Foreground time is summed from events, not from `queryUsageStats`.** Its
`INTERVAL_DAILY` buckets are not aligned to local midnight and its
`totalTimeInForeground` is inconsistent between vendors. Summing
`ACTIVITY_RESUMED` → `ACTIVITY_PAUSED` pairs is what agrees with the number
Digital Wellbeing already shows on the phone, and agreeing with that number is
the whole credibility of this app.

**There is no API for stopping an app from launching.** `GuardService` is an
`AccessibilityService`: it is told when a window comes to the front and calls
`performGlobalAction(GLOBAL_ACTION_HOME)`. It also posts a delayed re-check for
the remaining budget — without that, an app opened at 29 minutes of 30 fires no
further event and you scroll past the limit forever.

**Rules are written twice.** Dart owns them; every mutation mirrors the same
JSON into a native `SharedPreferences` file, because by the time an app is
coming to the front there is usually no Flutter engine alive to ask. Not the
plugin's `FlutterSharedPreferences` file — that is someone else's format, and
it is migrating to DataStore.

**Days are `'YYYY-MM-DD'` strings and day arithmetic goes through the
`DateTime` constructor.** A `Duration` is 24 real hours and lands on the wrong
calendar day across a DST change.

**`onAccent` is computed per theme, not per app.** White on the dial measures
4.64:1 and navy 3.01; on the lifted night dial it inverts to navy 5.12 and
white 2.72. Wick hardcodes white and Penny hardcodes navy — Tick cannot do
either. `test/palette_test.dart` asserts both.

**Gold is a ground, never a shape.** On cream it measures 1.56:1 and simply
disappears. It may only appear underneath ink, which it carries at 8.44:1.

**Nothing scolds.** An app that has spent its budget is *done for today*, drawn
in the family's success colour. Red is reserved for destructive confirmation,
never for going over a limit you set yourself.

## What Tick asks for, and why

| | |
|---|---|
| **Usage access** | The whole app. An appop, granted by hand in Settings — it cannot be requested with a dialog. |
| **Accessibility** | Enforcement. `guard_service.xml` requests `typeWindowStateChanged` only and does **not** set `canRetrieveWindowContent`, so Tick cannot see inside the apps it watches. |
| **Notifications** | The "time's up" message. Without it the kick home still happens, silently. |
| **Notification access** | Optional, opt-in from Insights. Counts forward only; there is no history to backfill. |
| **`QUERY_ALL_PACKAGES`** | Usage records are bare package names; resolving one to a label and an icon needs package visibility on API 30+. |

## Mascot

Six poses, no disappointed one. The `Tick` enum names them by the family's pose
vocabulary (`standing · focus · complete · thinking · celebrate · rest`) and
maps each to the filename on Tick's own character sheet — `Tick.complete` is
the pose the sheet calls "Block", because an app that has used its time is
finished, not punished.

```
art/                      hand-made, never bundled
  character-sheet.png
  mascot-source/          the six poses at ~1250px, plus the launcher crop
assets/                   generated by tool/make_icon.py, never hand-edited
  mascot/  icon/  splash/
```

**Run `python3 tool/make_icon.py` after changing any source art**, then
`dart run flutter_launcher_icons`.

Constrain **height only** — the poses do not share an aspect ratio. A missing
pose falls back to `standing`, and `standing` falls back to `ClockMark`, a
drawn clock. That fallback is why every screen in this repo renders in a
checkout with no art in it at all.

The adaptive foreground bottom-aligns to the canvas so the crop's cut edge runs
off the bottom, where the mask hides it — **zero bottom padding**, same as Penny
and Wick. A gap under the mascot means someone framed to the 72dp safe box by
mistake. That box is where content is *guaranteed* to survive, not the region a
launcher displays: launchers mask the whole 108dp layer. Render a candidate
against a mask inscribed in the full canvas, and check it beside `../penny` and
`../wick` before believing it.

## Design

`../design-system.html` is the contract, and Wick is the reference
implementation. Tick differs from it in the accent alone: dial `#7C5CE6`, navy
`#16295C`, cream `#FDF8F3`. The mascot's orange (`#FE7F41`) stays baked into
the art and never enters the chrome, or Tick and Wick blur.

One deliberate divergence: the shell's tab is 48 tall rather than the siblings'
44, which fails `androidTapTargetGuideline`. See `test/a11y_test.dart`.

See `PLAN.md` for what the plan got wrong.
