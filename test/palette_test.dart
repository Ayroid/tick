import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tick/theme.dart';

/// [fg] at [alpha] painted over [bg] — what a tinted well actually resolves to.
Color over(Color fg, double alpha, Color bg) =>
    Color.alphaBlend(fg.withValues(alpha: alpha), bg);

/// What `onAccent()` computes, without a BuildContext.
Color onAccentOf(Color accent) =>
    contrastBetween(navy, accent) >= contrastBetween(Colors.white, accent)
    ? navy
    : Colors.white;

void main() {
  group('the brand accent', () {
    // The one place Tick's palette behaves differently from either sibling.
    // Wick hardcodes white on its flame; Penny hardcodes navy on its sprout.
    // The dial does neither, because the winner is not the same in both
    // themes — which is exactly the case the design system says cannot be
    // tabulated, and the reason `appTheme` computes it per theme instead of
    // taking a const.
    test('on-accent flips between themes — light takes white, dark navy', () {
      expect(onAccentOf(dial), Colors.white);
      expect(onAccentOf(dialDark), navy);
    });

    test('white carries a button label on the dial, navy does not', () {
      expect(contrastBetween(Colors.white, dial), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(navy, dial), lessThan(4.5));
    });

    test('navy carries a button label on the lifted dial, white does not', () {
      expect(contrastBetween(navy, dialDark), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(Colors.white, dialDark), lessThan(4.5));
    });

    // The margin over 4.5 is 0.14. The mascot sheet's own violet (#8B6DEE)
    // measures 3.80 against white and 3.67 against navy — it fails both, and
    // ships deepened one step to get here. Anything that retunes the accent
    // has this little room, so it is pinned rather than left to be noticed.
    test('the light-mode margin is thin, and known to be thin', () {
      final margin = contrastBetween(Colors.white, dial) - 4.5;
      expect(margin, greaterThan(0));
      expect(
        margin,
        lessThan(0.5),
        reason: 'if this grew, the accent moved — update the note',
      );
    });
  });

  group('text on the page', () {
    test('body text passes in both themes', () {
      expect(contrastBetween(navy, warmBg), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, darkBg), greaterThanOrEqualTo(4.5));
    });

    test('secondary text passes in both themes', () {
      expect(contrastBetween(navySoft, warmBg), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkMuted, darkBg), greaterThanOrEqualTo(4.5));
    });

    test('body text passes on a sunk fill — inputs, the segmented track', () {
      expect(contrastBetween(navy, warmSunk), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, darkSunk), greaterThanOrEqualTo(4.5));
    });

    test('ink carries on the accent at wash strength', () {
      expect(contrastBetween(navy, dialSoft), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, dialSoftDark), greaterThanOrEqualTo(4.5));
    });
  });

  group('bars and rings', () {
    // Every chart in Tick is drawn in the accent — there is no second
    // quantity, so no second hue. Unlike Penny's sprout, the dial is dark
    // enough to clear WCAG 1.4.11 for a graphical object on both grounds,
    // which means a bar needs no documented exception here.
    test('a dial bar reads against the page', () {
      expect(contrastBetween(dial, warmBg), greaterThanOrEqualTo(3.0));
      expect(contrastBetween(dialDark, darkBg), greaterThanOrEqualTo(3.0));
    });

    test('a dial bar reads against a card', () {
      expect(contrastBetween(dial, Colors.white), greaterThanOrEqualTo(3.0));
      expect(contrastBetween(dialDark, darkCard), greaterThanOrEqualTo(3.0));
    });

    test('a spent ring is distinct from its unspent track', () {
      for (final dark in [true, false]) {
        final accent = dark ? dialDark : dial;
        final ground = dark ? darkBg : warmBg;
        final track = over(
          accent,
          dark ? 0.16 : 0.26,
          over(accent, dark ? 0.07 : 0.035, ground),
        );
        expect(
          contrastBetween(accent, track),
          greaterThanOrEqualTo(3.0),
          reason: '${dark ? 'dark' : 'light'}: the ring has no gap',
        );
      }
    });
  });

  group('gold — the done state', () {
    // Gold says an app has spent its budget. That is "done", which is what the
    // family's success colour already means, so Tick adds no twelfth token and
    // never reaches for red: going over a limit you set is not a failure.

    test('ink carries on a gold fill — the rule is never white on yellow', () {
      expect(contrastBetween(navy, gold), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(navy, goldDark), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(Colors.white, gold), lessThan(4.5));
      expect(contrastBetween(Colors.white, goldDark), lessThan(4.5));
    });

    // Gold on cream is 1.56:1 — invisible. This is not a defect to work
    // around, it is a constraint on where gold may appear: as a ground under
    // ink, never as a bare shape on the page. The test exists so nobody
    // "fixes" a done-state by drawing a gold bar and wondering why it vanished.
    test('gold is a ground, not a shape — it disappears on cream', () {
      expect(contrastBetween(gold, warmBg), lessThan(3.0));
      expect(contrastBetween(gold, Colors.white), lessThan(3.0));
    });

    test('at night it may be a shape — the ground is dark enough', () {
      expect(contrastBetween(goldDark, darkBg), greaterThanOrEqualTo(3.0));
    });

    test('gold and the dial are told apart in greyscale', () {
      // They appear together: a ring in the dial, its done-chip in gold.
      expect(contrastBetween(dial, gold), greaterThanOrEqualTo(1.4));
      expect(contrastBetween(dialDark, goldDark), greaterThanOrEqualTo(1.4));
    });

    test('ink carries on gold at wash strength', () {
      expect(contrastBetween(navy, goldSoft), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, goldSoftDark), greaterThanOrEqualTo(4.5));
    });
  });

  group('chips', () {
    test('a chip label survives its own well at night', () {
      final well = over(dialDark, 0.15, over(dialDark, 0.07, darkBg));
      expect(contrastBetween(dialDark, well), greaterThanOrEqualTo(4.5));
    });

    test('a chip label takes the foreground on cream, not the accent', () {
      // Rule 4: small text on a light tint cannot carry the accent. The dial
      // on its own 12% well over cream falls short, which is why `onTint`
      // hands back onSurface in light mode. Asserting the shortfall keeps the
      // rule from being "simplified" away later.
      final well = over(dial, 0.12, over(dial, 0.035, warmBg));
      expect(contrastBetween(dial, well), lessThan(4.5));
      expect(contrastBetween(navy, well), greaterThanOrEqualTo(4.5));
    });
  });
}
