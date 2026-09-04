import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'clock.dart';

// ── Tick palette ────────────────────────────────────────────────────────────
// Tick is a white alarm clock with an orange bell, outlined in navy, drawn on
// warm cream.
//
//   navy   structures — it is the outline colour of every piece of the art
//   dial   is the brand — the ring, the primary action, every chart bar
//   gold   is done — an app that has spent its budget for the day
//
// The accent came off the mascot sheet's own "Stay Focused" swatch (#8B6DEE)
// and then had to move: that violet measures 3.80:1 against white and 3.67
// against navy, so it fails a 15px/700 button label whichever foreground it
// takes. It ships deepened one step, to #7C5CE6, where white clears 4.5 — by
// 0.14, which is thin, and pinned in test/palette_test.dart so a retune of the
// tints cannot quietly push it under.
//
// The mascot's bell is orange (#FE7F41) and Wick's flame is #FD5500. The
// orange stays baked into the mascot PNGs and never enters Tick's chrome, or
// the two apps blur — the same rule Penny applied to the same colour.

const navy = Color(0xFF16295C);
const navySoft = Color(0xFF33487C);
const dial = Color(0xFF7C5CE6);
const dialSoft = Color(0xFFF2ECFB);
const warmBg = Color(0xFFFDF8F3);
const warmSunk = Color(0xFFF4EFEA);
const warmGray = Color(0xFFDED6CC);

// Done — an app that has spent its budget for the day.
//
// GOLD IS A GROUND, NEVER A SHAPE. On cream it measures 1.56:1 and simply
// disappears; on a card it is 1.65. So it may only ever appear underneath ink,
// which it carries at 8.44:1 — a chip, a pill, a filled cell in a dark well.
// A gold bar or a gold ring on the page is invisible, and the palette test
// asserts the shortfall so that is a decision rather than a discovery.
//
// It is the family's success colour unchanged, because "spent its budget" is
// what "done" means. Tick adds no twelfth token for it, and never reaches for
// red: going over a limit you set for yourself is not a failure, and the one
// tone rule the design system calls non-negotiable is that nothing scolds.
const gold = Color(0xFFFDC000);
const goldSoft = Color(0xFFFFF3D6);

// Dark is derived, not designed: the same palette on a neutral black ground,
// each colour lifted until it holds contrast. No new hues for night.
const darkBg = Color(0xFF0A0A0A);
const darkCard = Color(0xFF171717);
const darkSunk = Color(0xFF262626);
const darkInk = Color(0xFFFAFAFA);
const darkMuted = Color(0xFFA3A3A3);
const dialDark = Color(0xFFA78BFA);
const dialSoftDark = Color(0xFF1E1729);
const goldDark = Color(0xFFFFD24D);
const goldSoftDark = Color(0xFF332913);

const radius = 16.0;
const pill = 999.0;
const fontFamily = 'PlusJakartaSans';

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Brand accent — the dial. Primary actions, progress rings, every chart bar.
Color dialOf(BuildContext c) => isDark(c) ? dialDark : dial;
Color dialSoftOf(BuildContext c) => isDark(c) ? dialSoftDark : dialSoft;

/// Done. A ground that carries ink — see the note on [gold] for why it is
/// never the shape itself.
Color goldOf(BuildContext c) => isDark(c) ? goldDark : gold;
Color goldSoftOf(BuildContext c) => isDark(c) ? goldSoftDark : goldSoft;

/// Soft shadow, brand-tinted in light and plain black in dark. The brand
/// separates surfaces with tint, not with rules — this is for the few surfaces
/// that genuinely float.
List<BoxShadow> cardShadow(bool dark) => dark
    ? const [
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 14,
          offset: Offset(0, 3),
        ),
      ]
    : const [
        BoxShadow(
          color: Color(0x1216295C),
          blurRadius: 16,
          offset: Offset(0, 3),
        ),
      ];

ThemeData appTheme({required bool dark}) {
  final bg = dark ? darkBg : warmBg;
  final card = dark ? darkCard : Colors.white;
  final fg = dark ? darkInk : navy;
  final muted = dark ? darkMuted : navySoft;
  final sunk = dark ? darkSunk : warmSunk;
  final border = dark ? darkSunk : warmGray;
  final accent = dark ? dialDark : dial;

  // What goes on a full-strength accent fill. Measured, not assumed — and
  // unlike either sibling this is not a constant, because the winner is not
  // the same in both themes. White on #7C5CE6 is 4.64 and navy 3.01; on the
  // lifted #A78BFA it inverts to navy 5.12 and white 2.72. Wick hardcodes
  // white and Penny hardcodes navy; Tick cannot do either.
  final onAccentConst = dark ? navy : Colors.white;

  TextStyle t(
    double size,
    FontWeight w, {
    Color? color,
    double spacing = -0.2,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: w,
    color: color ?? fg,
    letterSpacing: spacing,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: bg,
    // InkSparkle is Android's Material 3 splash, and it draws itself with a
    // shader loaded from an asset. That resolves fine on Android; on desktop
    // the lookup can fail after a hot restart and then throws on every single
    // tap. Nothing about the brand depends on which of the two ripples runs,
    // so everywhere else gets the shader-free one.
    splashFactory: defaultTargetPlatform == TargetPlatform.android
        ? InkSparkle.splashFactory
        : InkRipple.splashFactory,
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccentConst,
      secondary: muted,
      onSecondary: bg,
      tertiary: dark ? goldDark : gold,
      onTertiary: navy,
      surface: card,
      onSurface: fg,
      surfaceContainerHighest: sunk,
      outline: border,
      error: const Color(0xFFDC2626),
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: t(17, FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: sunk,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: t(14, FontWeight.w400, color: muted),
      border: _softBorder(Colors.transparent),
      enabledBorder: _softBorder(Colors.transparent),
      focusedBorder: _softBorder(accent, width: 1.5),
    ),
    // Primary action only — the brand asks that the dial stay meaningful.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccentConst,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        textStyle: t(15, FontWeight.w700, color: onAccentConst),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    // Secondary: the accent at wash strength with ink text.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: dark ? dialSoftDark : dialSoft,
        minimumSize: const Size.fromHeight(52),
        textStyle: t(15, FontWeight.w700),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        textStyle: t(14, FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      // Sheets carry the PAGE ground, not the card ground, so they read as the
      // app rising up rather than a panel landing on it.
      backgroundColor: bg,
      surfaceTintColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: t(18, FontWeight.w700),
      contentTextStyle: t(14, FontWeight.w400, color: muted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? darkSunk : navy,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: t(11, FontWeight.w600, color: Colors.white),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    textTheme: TextTheme(
      headlineLarge: t(29, FontWeight.w800, spacing: -0.7),
      titleLarge: t(21, FontWeight.w700, spacing: -0.4),
      titleMedium: t(15, FontWeight.w600),
      bodyLarge: t(15, FontWeight.w400),
      bodyMedium: t(14, FontWeight.w400),
      bodySmall: t(13, FontWeight.w400, color: muted),
      labelLarge: t(13, FontWeight.w700),
      labelSmall: t(11.5, FontWeight.w500, color: muted),
    ),
  );
}

OutlineInputBorder _softBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
      borderRadius: BorderRadius.circular(14),
    );

const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const weekdayShort = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String longDate(DateTime d) =>
    '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';

String shortDate(DateTime d) =>
    '${monthShort[d.month - 1]} ${d.day}, ${d.year}';

/// `1 app` / `3 apps`. [many] for words that do not just take an s.
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : many ?? '${one}s'}';

String greeting() {
  final h = clock().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// A card the way the brand draws one: no border, soft shadow, large radius.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: cardShadow(isDark(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// The colour of whatever we are inside.
///
/// Penny threads a per-category colour down its tree here; Tick has nothing
/// that is per-item coloured — an app carries its own launcher icon, which is
/// its colour — so this is the brand, always. The indirection stays because
/// every tint below is written against it.
Color accentOf(BuildContext c) => dialOf(c);

/// A colour that can carry small text against a tinted well.
///
/// At night that is the accent itself. In light it is not, and cannot be: the
/// dial on its own 12% well over cream lands short of the 4.5:1 a 12px label
/// needs. Let the fill and the glyph carry the colour; the text takes the
/// normal foreground and lets weight do the work.
Color onTint(BuildContext c) =>
    isDark(c) ? accentOf(c) : Theme.of(c).colorScheme.onSurface;

/// WCAG relative contrast between two opaque colours.
double contrastBetween(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// What goes *on* a full-strength accent fill — a duration, a glyph.
///
/// Whichever of the two actually wins, not whichever a lightness threshold
/// guesses. For the dial the answer genuinely flips: white in light, navy at
/// night. That is the case the design system says cannot be tabulated, and
/// here it is, in the brand colour rather than in some outlying swatch.
Color onAccent(BuildContext c) {
  final a = accentOf(c);
  return contrastBetween(navy, a) >= contrastBetween(Colors.white, a)
      ? navy
      : Colors.white;
}

// ── Tinted surfaces ─────────────────────────────────────────────────────────
// Nine tenths of the surfaces in the app are the accent at some alpha over the
// page ground. A screen picks a role, not a number.

/// The current accent at [alpha]. Everything below builds on it.
Color tint(BuildContext c, double alpha) =>
    accentOf(c).withValues(alpha: alpha);

/// Card ground. Barely there in light, where a wash on cream goes muddy fast.
Color cardTint(BuildContext c) => tint(c, isDark(c) ? 0.07 : 0.035);

/// The hairline around a card, and around the grid well inside it.
Color cardEdge(BuildContext c) => tint(c, isDark(c) ? 0.16 : 0.13);

/// The panel a chart sits in. On cream there is no panel: the chart sits
/// straight on the card so the card's hover and press ink reach it. Dark mode
/// keeps a well; the palette needs a ground darker than the card to be seen.
Color gridWell(BuildContext c) =>
    isDark(c) ? Color.alphaBlend(tint(c, 0.07), darkBg) : Colors.transparent;

/// An unspent bar, an unlit cell, a ring's track — present, clearly not
/// filled. Always read against [gridWell] or the card, never against the page.
Color cellEmpty(BuildContext c) => tint(c, isDark(c) ? 0.16 : 0.26);

/// Chart furniture: weekday initials, hour labels, axis ticks. `secondary` at
/// full strength competes with the bars it labels.
Color gridLabel(BuildContext c) => isDark(c)
    ? Colors.white.withValues(alpha: 0.45)
    : navySoft.withValues(alpha: 0.85);

/// Icon tiles and chips sit one step up from the card ground.
Color chipFill(BuildContext c) => tint(c, isDark(c) ? 0.15 : 0.12);

/// Small labels — durations, counts, dates, percentages. Monospace on purpose:
/// it is what makes a wall of digits read as data rather than prose, and the
/// family is the platform's own so nothing has to be bundled.
const monoFamily = 'monospace';

TextStyle mono(
  double size, {
  required Color color,
  FontWeight weight = FontWeight.w500,
  double spacing = 0.4,
}) => TextStyle(
  fontFamily: monoFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
);

/// A strut that pins a line's height to the font size, whatever glyphs land
/// in it.
///
/// A duration swaps between `1h 24m`, `12m` and `<1m` as the day goes on, and
/// `<` is not guaranteed to be in the platform mono — a fallback font with its
/// own ascent and descent would resize the line and move everything below it.
StrutStyle monoStrut(double size) =>
    StrutStyle(fontFamily: monoFamily, fontSize: size, forceStrutHeight: true);

/// A round icon button in a soft well — the only chrome shape used for
/// navigation.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  /// Primary action — the accent disc rather than the neutral well.
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        // The disc is 40 (or 36 for the period arrows), but the thing you can
        // hit is never below 48 — the one rule the design system calls
        // non-negotiable. The extra is invisible padding around the circle.
        child: SizedBox(
          width: size < 48 ? 48 : size,
          height: size < 48 ? 48 : size,
          child: Center(
            child: Material(
              color: filled
                  ? dialOf(context)
                  : (isDark(context) ? darkSunk : const Color(0xFFF1EAE2)),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    icon,
                    size: size * 0.5,
                    // Computed, not white: on the lifted dial white is 2.72:1.
                    color: filled ? onAccent(context) : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card content lives in: tinted ground, hairline edge, no shadow. Cards
/// are told apart from the page by tint, not by elevation.
class TintCard extends StatelessWidget {
  const TintCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.onLongPress,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overrides the tinted ground while keeping the accent's hairline — for a
  /// card that wants the colour at its edge but not under its content.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // Over the *page* ground, not the raised surface colour: starting a
        // step lighter would undo the tint that does the separating.
        color:
            color ??
            Color.alphaBlend(
              cardTint(context),
              Theme.of(context).scaffoldBackgroundColor,
            ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardEdge(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A pill of mutually exclusive choices — the one picker shape. More than
/// three options is a list, not a segmented control.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Choice -> label, in the order they should read.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = options.keys.toList();
    final index = keys.indexOf(value);
    final accent = dialOf(context);
    final ink = onAccent(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(pill),
      ),
      child: Stack(
        children: [
          // The pill slides between positions rather than each segment fading
          // its own background in and out — the same movement the tab bar
          // makes, and the same 250ms easeOut it animates a page change with.
          // A pill that fades in place reads as two things blinking; one that
          // travels reads as the selection moving, which is what happened.
          if (index >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: keys.length == 1
                    ? Alignment.center
                    : Alignment(-1 + 2 * index / (keys.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / keys.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(pill),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final key in keys)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: key == value,
                    label: options[key]!,
                    excludeSemantics: true,
                    onTap: () => onChanged(key),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(key),
                      child: ConstrainedBox(
                        // A floor rather than tuned padding: the label's
                        // height depends on the font, and 48 is the one
                        // number the design system calls non-negotiable.
                        // minHeight, so it still grows if the person
                        // scales their text up.
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            style: TextStyle(
                              fontFamily: fontFamily,
                              fontSize: 13,
                              // Weight as well as colour, so the selection is
                              // legible without relying on colour alone.
                              fontWeight: key == value
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: key == value ? ink : scheme.secondary,
                            ),
                            child: Text(
                              options[key]!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small pill: tinted well, accent glyph, mono label.
class TintChip extends StatelessWidget {
  const TintChip({
    super.key,
    required this.icon,
    required this.label,
    this.semanticsLabel,
    this.dim = false,
    this.done = false,
  });

  final IconData icon;
  final String label;
  final String? semanticsLabel;

  /// Nothing to report yet — a zero reads muted rather than lit.
  final bool dim;

  /// Spent its budget. The one place gold appears, and it appears as a ground
  /// under ink — see the note on [gold].
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // The unlit cell's own ground, with the accent as ink for both glyph and
    // label, so the pill and any chart below it read as one surface.
    // Deliberately below the 4.5:1 a 12px label normally wants on cream: the
    // semantics label carries the same words for anyone who cannot read them.
    final ground = done
        ? goldOf(context)
        : dim
        ? scheme.surfaceContainerHighest
        : cellEmpty(context);
    final ink = done
        ? navy
        : dim
        ? scheme.secondary
        : onTint(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: done
                ? navy
                : dim
                ? scheme.secondary
                : accentOf(context),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            semanticsLabel: semanticsLabel,
            strutStyle: monoStrut(12),
            style: mono(12, color: ink, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
