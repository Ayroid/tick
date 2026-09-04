# Tick — screen time, and limits that hold

*Know your time. Take back control.*

## Context

Third app in the family, after Wick (habits) and Penny (money). Tick shows
where the day went, app by app, and lets you spend a daily budget on the ones
that eat it.

Two halves, and only one of them needs storage:

- **Viewing** is free. Android's `UsageStatsManager` has been recording per-app
  foreground time since the phone was first switched on. Tick asks for it; it
  does not track anything itself, does not run in the background to count, and
  has no session table.
- **Limiting** is a lie Android does not let you tell honestly. There is no API
  to stop an app launching. What exists is an `AccessibilityService`, which is
  told when a window comes to the front and can send the user back to the home
  screen. That is what every blocker on the Play Store does, and it is what
  Tick does. The app says so out loud rather than implying a lock that isn't
  there.

Everything else is Wick's architecture, unchanged.

**Settled before building:** enforcement is a home-kick plus a notification (no
overlay permission); v1 carries per-app daily limits, focus sessions and
schedules, weekly and monthly stats, and unlock/open counts; limits are freely
editable at any time, including mid-block.

## Palette — Tick's row in the registry

| token | light | dark |
|---|---|---|
| `dial` (accent) | `#7C5CE6` | `#A78BFA` |
| `dialSoft` | `#F2ECFB` | `#1E1729` |
| `ink` | `#16295C` | `#FAFAFA` |
| `bg` | `#FDF8F3` | `#0A0A0A` |
| `sunk` | `#F4EFEA` | `#262626` |
| `gold` (success) | `#FDC000` | `#FFD24D` |

Accent noun is **`dial`**, matching `flame` and `sprout`.

### The mascot sheet's violet cannot carry a label

```
#8B6DEE   vs white 3.80    vs navy 3.67      ← the sheet's swatch, fails both
#7C5CE6   vs white 4.64 ✓  vs navy 3.01      ← shipped
```

It ships deepened one step. The margin over 4.5 is **0.14**, asserted in
`test/palette_test.dart` so a retune cannot quietly push it under.

### The orange stays in the art

The mascot's bell is `#FE7F41`; Wick's flame is `#FD5500`. Penny already
settled this case — the marketing orange stays baked into the PNGs and never
enters the chrome, or the apps blur.

### No twelfth token, and no red for going over

Over budget is *done*, which is what `success` already means. Red stays
reserved for destructive confirmation.

## Architecture — Wick's, unchanged

One `ChangeNotifier` in `store.dart`; one JSON blob plus scalars in
`shared_preferences`; `'YYYY-MM-DD'` day keys; migrations as defensive reads
inside `fromJson`, not a version chain; imperative navigation with a top-level
opener beside each screen; `PageView` + floating `PageTabs`; maths in
widget-free files; comments explain why, including rejected alternatives.

The one departure: Tick has a platform channel, and the siblings have none.

## Data model

```
rules      { limits: {pkg: minutes}, schedules: [...], focus: {until, packages} }
archive    { 'YYYY-MM-DD': {pkg: ms} }   — finished days only, never today
themeMode / onboarded / lastArchived
```

Every rules mutation writes twice: `shared_preferences` for the next launch,
and `setRules(json)` down the channel for the guard, which has to decide
whether to block an app when there is usually no Flutter engine alive to ask.

## Verification

```sh
flutter analyze
flutter test                    # 132 unit, widget, a11y and golden tests
flutter test --update-goldens   # only when a pixel change is deliberate
tool/release.sh
```

| test | protects |
|---|---|
| `palette_test.dart` | every contrast pair per theme, incl. the 0.14-margin accent |
| `duration_test.dart` | ms → string at the boundaries |
| `analytics_test.dart` | span boundaries, the archive/live seam, calendar days |
| `store_test.dart` | rules round-trip, wrap-midnight schedules, corrupt blobs, backup |
| `app_test.dart` | the flows, with the channel mocked |
| `a11y_test.dart` | tooltip + semantics on icon-only controls, 48px targets, row merging |
| `golden_test.dart` | 11 images, light and dark |

`test/fake_phone.dart` stubs the channel. **No test needs a device.**

### Still to run, on a real phone

None of this can be exercised without hardware, and none of it was:

1. Grant usage access. Today's numbers **match Digital Wellbeing**.
2. A 1-minute limit. Open the app and wait past a minute *while still inside
   it* — the delayed re-check must kick you home without an app switch first.
3. Reopen: blocked at once, notification posted.
4. Raise the limit while blocked — reopening works.
5. A 10-minute focus session over three apps; a fourth is unaffected; it
   expires on its own.
6. A 22:00–07:00 schedule blocks across midnight.
7. Reboot: the service comes back.
8. Turn accessibility off in Settings — Limits shows the guard card rather than
   pretending to work.

## Changes during the build

Seven things the plan got wrong, found by writing the tests, looking at the
goldens, and rendering the launcher mask. Recorded here rather than quietly
edited above.

**1. `onAccent` is not a constant here.** The plan said white, having measured
only the light accent. Measured in both themes it flips: white on `#7C5CE6` is
4.64 and navy 3.01, but on the lifted `#A78BFA` it inverts to navy 5.12 and
white 2.72. Wick hardcodes white, Penny hardcodes navy — Tick computes it per
theme. This is the exact case the design system says cannot be tabulated, and
it turned up in the brand colour rather than in some outlying swatch.

**2. Gold cannot be a shape.** The plan had the budget ring "landing on gold"
when spent. Gold on cream measures 1.56:1 and on a card 1.65 — it is invisible.
It became a rule instead: gold is a ground under ink and never a bare shape,
asserted as a *shortfall* in `palette_test.dart` so nobody later "fixes" a
done-state by drawing a gold bar. The ring completes in the dial; the done
state is a gold chip with navy ink.

**3. Every bar in the app rendered at zero size.** `FractionallySizedBox` with
only one factor set passes a **loose** constraint on the other axis, and a
childless `DecoratedBox` under a loose constraint collapses to nothing. The
week chart was blank and the app rows were drawing only their track. Both
needed the second factor pinned to 1. Invisible to a widget test — `find` finds
the widget whatever size it rendered at — and obvious in the first golden.
**This is the case for goldens, in one bug.**

**4. The shell tab was too small.** Copied from Penny at 44 tall, which fails
`androidTapTargetGuideline` outright. Raised to 48, which is the one number the
design system calls non-negotiable, and is a deliberate divergence from both
siblings — the sheet's own rule says fix it upstream, so `page_bar.dart` in
Wick and Penny should follow.

**5. The limit sheet clipped its own Save button.** The minutes step is taller
than a small phone once the presets wrap. Fixed by scrolling the choosing and
pinning the deciding: `Flexible(SingleChildScrollView(...))` with the buttons
outside it.

**6. A schedule card read the wall clock.** `DateTime.now()` instead of
`clock()`, so a 22:00–07:00 bedtime showed "On now" at half past ten in the
morning. Everything date-shaped goes through `clock.dart`; this one had been
missed, and a golden taken after 22:00 would have hidden it.

**7. The adaptive icon cut the mascot's face off.** `tool/make_icon.py` came
from Penny, which frames the launcher crop off its *width* and oversizes it
past the 2/3 guarantee, then bottom-aligns to the canvas so the cut edge hides
under the mask. That is right for a coin — a round mascot whose face sits in
the middle of its own crop. Tick is wider than tall (1123×907 trimmed) with its
face low in the crop, and the same rule put the eyes entirely below the
launcher's circle. Driving off *height* instead and letting the width bleed
past the box fixes it; the sides the mask clips are the body's own rounded
edges and lose nothing.

`ADAPTIVE_OVERSIZE` is gone, replaced by `ADAPTIVE_HEIGHT = 0.94` and
`ADAPTIVE_TOP_PAD = 0.05`. Both were **tuned by eye against a rendered mask**,
and had to be: at 1.00/0.00 the circle shaves the top corners off the bell, and
past about 1.10 it takes the eyes. Every value in that range looked fine as
arithmetic and wrong as a picture. Re-render the mask before trusting a new
number.

**8. The number the whole app exists to show was wrong by 21x.**

Found on a real phone, on the first run: 17756 hours of screen time "today",
with a launcher reporting 5144 hours across 345 opens.

Android fires `ACTIVITY_PAUSED` and then `ACTIVITY_STOPPED` for the same
activity, and `Usage.between` treated both as a close. The PAUSED consumed the
stored open-time; the STOPPED found nothing, fell through to the "then it must
have been open since the window began" fallback, and added the entire elapsed
day — once per app switch.

The fallback itself was right and is still there; what was wrong was letting
every unmatched close take it. Exactly one app can have been in front when the
window opened, so that credit is now available exactly once, before the first
RESUMED.

Rewritten as a single-foreground fold — one current package and the instant it
came forward — because only one app is ever in front. That is not a
simplification of the map version, it is the thing that makes the sum correct.

`Usage.fold` is now a pure function over a list of plain `Moment`s, with
`between` doing nothing but translating the system cursor into them. That buys
11 JUnit tests that run on the JVM with no device
(`cd android && ./gradlew :app:testDebugUnitTest`), including the one that
matters: a day of switching can never total more than the day. The old
algorithm fails it by 21x.

**This is the cost of the manual script going unrun.** Every automated test
passed against a mocked channel that returned well-formed windows, because the
mock could not produce the event shape the bug needed — a PAUSED followed by a
STOPPED. The fixture was written from how the stream was assumed to look.

**9. A pause is not the end of a session, and the home screen is not an app.**

The 21x fix got the arithmetic right and the model still wrong. Checked against
Digital Wellbeing on a real day — 8h31 there, 8h08 in Tick — every app matched
to the minute except two, and the two were the whole gap:

| | Wellbeing | Tick | opens |
|---|---|---|---|
| WhatsApp | 1h37 | 30m | 329 |
| Instagram | 55m | 37m | 76 |
| Penny | 1h1 | 1h1 | 40 |
| Clock | 50m | 50m | 12 |

Ending a session on `ACTIVITY_PAUSED` throws away every gap between a pause and
the next resume. Apps pause constantly for things nobody perceives as leaving
the app — a system dialog, the shade, a sub-activity, a cancelled gesture — and
the apps with that churn bled minutes while the ones without matched exactly.
Penny with 40 clean launcher switches lost nothing; WhatsApp with 329 cycles
lost 67 minutes.

A session now runs until **another app comes to the front**, the screen goes
off, or the window ends. Pauses are ignored. Screen-off handling
(`SCREEN_NON_INTERACTIVE`, `KEYGUARD_SHOWN`, `DEVICE_SHUTDOWN`) is what stops a
phone put down mid-app accruing time, and is the price of not ending on a
pause.

The second half: Wellbeing's 8h31 total is the sum of its app list, and the
list has no home screen in it. Tick was reporting `com.nothing.launcher` as the
second heaviest row at 1h11 across 363 opens, plus `packageinstaller` at 105
opens, `permissioncontroller`, `intentresolver`. Usage for a package that has
no launcher entry is now dropped — one rule, and it removes all of them. A
screen-time app whose top result is the home screen is answering a question
nobody asked.

Sessions are disjoint by construction now — `since` only moves forward, to an
event's own timestamp — so no stream can total more than the window it covers.
That is a structural guarantee rather than a test, and it is exactly what the
first version violated by four orders of magnitude.

### Smaller amendments

- **`app_row.dart` was not in the plan.** The app-with-a-bar row is used on
  Today, Limits and Insights, and the house rule is that a widget used twice
  moves out of the screen. `AppIcon` lives with it, including the initial-on-a-
  tile fallback for an app that has been uninstalled since its time was
  recorded.
- **`test/fake_phone.dart` is shared**, against the family's convention of
  duplicating helpers per test file. Penny's helpers are five lines; this one
  is forty, and three divergent copies of a fake phone would be three different
  phones.
- **`budgetSpent` became `budgetToday`**, returning both numbers rather than a
  ratio, because the caption under the ring has to name what the ring is
  drawing. A percentage beside a duration it does not divide is two quantities
  on one card hoping nobody checks.
- **`Usage.between` seeds `openedAt` from the window start.** An app resumed
  before the window opened has no opening event inside it; without the seed its
  time is dropped and today's top app always reads short.
- **Notification counts land in the same native prefs file**, pruned to 31
  days — that file is rewritten on every notification the phone receives.
- **`LaunchFrame` shows `assets/splash/tick_mark.png`**, not the drawn
  `ClockMark` that Penny uses there. The mark is generated either way, and an
  unused generated asset is weight with no reader. `ClockMark` stays as the
  `errorBuilder`, so the frame still renders in a checkout with no art in it.
- **`golden_test.dart` needed `settleImages`.** Under fake async an
  `Image.asset` never resolves, so before the art existed every golden happily
  recorded the fallback mark. `precacheImage` does not help — `cacheHeight`
  wraps the provider in a `ResizeImage` with a different cache key.

## Ceilings deliberately accepted

- **A home-kick, not a block screen.** No `SYSTEM_ALERT_WINDOW`.
  `ponytail: home-kick only, add the overlay block card if the kick reads as a bug.`
- **Raw event history is ~7 days.** Hence the archive. Open Tick less than once
  a week and those days are gone. The alternative is a background service that
  counts, which is exactly what this app is for not doing.
- **The guard re-queries a day of events on every app switch**, cached 3s
  against notification spam only.
  `ponytail: full day re-query per app switch, cache the running total if it shows up in battery stats.`
- **The user can disable the accessibility service**, and nothing resists it.
  Limits are freely editable by decision; a lock on the off switch would be
  incoherent.
- **Notification counts start the day the listener is enabled.**
- **The whole rules blob is re-encoded on every mutation.** Irrelevant at this
  size.

## Not built

- **Uninstall protection, or resisting the accessibility toggle.** Incoherent
  with freely editable limits.
- **A "just 5 more minutes" snooze.** Raising the limit already is one, and it
  is the honest version of the same button.
- **Per-app colour.** An app carries its own launcher icon; that is its colour.
  `CatColor`, `catColors` and `CategoryAccent` are all deleted from the copied
  theme.
