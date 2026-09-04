import 'package:flutter_test/flutter_test.dart';
import 'package:tick/duration.dart';

void main() {
  group('humanMs', () {
    test('nothing, and less than nothing', () {
      expect(humanMs(0), '0m');
      // A corrupt archive or a clock that went backwards can hand this in.
      // It must not render as "-1h 59m".
      expect(humanMs(-1), '0m');
      expect(humanMs(-999999), '0m');
    });

    test('under a minute is visited, not used', () {
      expect(humanMs(1), '<1m');
      expect(humanMs(59999), '<1m');
    });

    test('the minute boundary', () {
      expect(humanMs(60000), '1m');
      expect(humanMs(119999), '1m');
      expect(humanMs(120000), '2m');
    });

    test('minutes up to the hour', () {
      expect(humanMs(59 * 60000), '59m');
    });

    test('the hour boundary drops the empty minutes', () {
      expect(humanMs(60 * 60000), '1h');
      expect(humanMs(120 * 60000), '2h');
    });

    test('hours and minutes together', () {
      expect(humanMs(84 * 60000), '1h 24m');
      expect(humanMs(61 * 60000), '1h 1m');
    });

    test('a whole day, and past one', () {
      // Two apps can each be foreground for part of the same minute on a
      // split screen, so a total above 24h is possible and must still render.
      expect(humanMs(24 * 60 * 60000), '24h');
      expect(humanMs(25 * 60 * 60000 + 30 * 60000), '25h 30m');
    });
  });

  group('shortMs — axis labels', () {
    test('zero is a bare zero, not a unit', () {
      expect(shortMs(0), '0');
      expect(shortMs(-5), '0');
    });

    test('a sliver still gets a minute rather than rounding to nothing', () {
      expect(shortMs(1), '1m');
      expect(shortMs(59999), '1m');
    });

    test('minutes below an hour', () {
      expect(shortMs(45 * 60000), '45m');
      expect(shortMs(59 * 60000), '59m');
    });

    test('hours round to the nearest, because a tick is not a sentence', () {
      expect(shortMs(60 * 60000), '1h');
      expect(shortMs(157 * 60000), '3h');
      expect(shortMs(150 * 60000), '3h');
      expect(shortMs(149 * 60000), '2h');
    });
  });

  group('limits', () {
    test('a limit renders like any other span', () {
      expect(humanMinutes(30), '30m');
      expect(humanMinutes(90), '1h 30m');
      expect(humanMinutes(0), '0m');
    });

    test('what is left', () {
      expect(remainingMs(0, 30), '30m');
      expect(remainingMs(10 * 60000, 30), '20m');
    });

    test('over the limit leaves nothing, never a negative', () {
      expect(remainingMs(31 * 60000, 30), '0m');
      expect(remainingMs(5 * 60 * 60000, 30), '0m');
    });
  });
}
