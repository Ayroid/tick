import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The mascot: a white alarm clock with an orange bell, outlined in navy.
///
/// Six poses, and deliberately no disappointed one. An app that runs out of
/// time gets the shield, not a scolding — see [Tick.complete].
///
/// The constants are the family's pose vocabulary; the filenames are the ones
/// on Tick's own character sheet. They differ, and the `asset` field is where
/// the two are reconciled. `Tick.complete` is the pose the sheet calls
/// "Block": an app that has spent its budget is finished for the day, which is
/// what complete means here, and the shield is the art for it.
enum Tick {
  standing('tick_default'),
  focus('tick_focus'),
  complete('tick_block'),
  thinking('tick_analyze'),
  celebrate('tick_achieve'),
  rest('tick_recharge');

  const Tick(this.asset);

  final String asset;

  String get path => 'assets/mascot/$asset.png';

  /// A missing pose falls back to the default rather than to a hole in the
  /// layout. The default itself falls back to the drawn mark.
  Tick? get fallback => this == Tick.standing ? null : Tick.standing;
}

/// One pose, at [size] tall.
///
/// Height only, never a square: the poses do not share an aspect ratio and
/// boxing them renders the wide ones short.
class TickImage extends StatelessWidget {
  const TickImage(this.pose, {super.key, this.size = 132, this.semanticLabel});

  final Tick pose;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      pose.path,
      height: size,
      fit: BoxFit.fitHeight,
      // The art is 512 tall and the largest use is 148. Without this a few MB
      // per pose sits in the image cache for no benefit.
      cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      errorBuilder: (context, _, _) => pose.fallback == null
          // Nothing left to fall back to — draw the mark instead of leaving a
          // gap. This is also what runs before the art has been dropped in.
          ? ClockMark(size: size, semanticLabel: semanticLabel)
          : TickImage(pose.fallback!, size: size, semanticLabel: semanticLabel),
    );
  }
}

/// Tick reduced to his silhouette: the clock body and the bell, drawn rather
/// than shipped.
///
/// Drawn because it has to scale from a 24px chip to a 512px splash mark and
/// recolour with the theme, which a raster cannot do. It is also what stands
/// in for a pose whose PNG is missing, so the app is complete before the art
/// is — every screen in this repo renders without a single mascot file.
class ClockMark extends StatelessWidget {
  const ClockMark({super.key, this.size = 132, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ClockPainter(dark: isDark(context)),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({required this.dark});

  final bool dark;

  // The character's own colours, not the semantic tokens. The bell is the
  // mascot's orange — the one that stays out of the chrome, see theme.dart.
  static const _face = Color(0xFFFFFFFF);
  static const _shade = Color(0xFFE6E3EC);
  static const _bell = Color(0xFFFE7F41);
  static const _bellShade = Color(0xFFE96A2E);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = dark ? const Color(0xFF0F1B3D) : navy;
    final stroke = s * 0.045;

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = line;

    // The body is a rounded square sitting low, with the bell above it. Its
    // corner radius is what keeps him a character rather than a clip-art
    // clock: a circle would read as an icon.
    final bodyW = s * 0.70, bodyH = s * 0.66;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - bodyH / 2 - stroke),
        width: bodyW,
        height: bodyH,
      ),
      Radius.circular(s * 0.20),
    );
    final centre = body.outerRect.center;

    // The bell, drawn first so the body's outline crosses in front of it.
    final bell = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centre.dx, body.outerRect.top - s * 0.035),
        width: bodyW * 0.42,
        height: s * 0.115,
      ),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(bell, Paint()..color = _bell);
    canvas.drawRRect(
      bell.deflate(stroke * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..color = _bellShade,
    );
    canvas.drawRRect(bell, outline);

    // Feet.
    for (final dir in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(
          centre.dx + dir * bodyW * 0.28,
          body.outerRect.bottom - s * 0.01,
        ),
        Offset(centre.dx + dir * bodyW * 0.40, size.height - stroke * 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.6
          ..strokeCap = StrokeCap.round
          ..color = line,
      );
    }

    canvas.drawRRect(body, Paint()..color = _face);
    canvas.drawRRect(body, outline);

    // The dial: a faint inner ring and four ticks, so he reads as a clock even
    // at the size of a chip where the eyes are two dots.
    final r = bodyW * 0.40;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.5
        ..color = _shade,
    );
    for (var i = 0; i < 4; i++) {
      final a = math.pi / 2 * i;
      final o = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        centre + o * (r * 0.86),
        centre + o * (r * 0.98),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.55
          ..strokeCap = StrokeCap.round
          ..color = line.withValues(alpha: 0.55),
      );
    }

    // Eyes.
    final eye = Paint()..color = line;
    for (final dir in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centre.dx + dir * r * 0.42, centre.dy - r * 0.12),
          width: r * 0.20,
          height: r * 0.32,
        ),
        eye,
      );
    }

    // A closed smile, never a frown.
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(centre.dx, centre.dy + r * 0.22),
        radius: r * 0.26,
      ),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.8
        ..strokeCap = StrokeCap.round
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) => old.dark != dark;
}

/// The empty-state block: a pose, a headline, one muted line, one action.
///
/// This is the mascot's main job — empty screens and quiet moments, never
/// decoration on a screen that already has content.
class TickMessage extends StatelessWidget {
  const TickMessage({
    super.key,
    this.pose = Tick.standing,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.size = 132,
  });

  final Tick pose;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TickImage(pose, size: size, semanticLabel: 'Tick'),
            const SizedBox(height: 18),
            Text(headline, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: text.bodySmall, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A celebration. One tap to dismiss, no score, nothing to beat.
Future<void> showTickMoment(
  BuildContext context, {
  Tick pose = Tick.celebrate,
  required String headline,
  required String body,
  String action = 'Nice',
}) {
  return showDialog<void>(
    context: context,
    // Ink at 32%, never plain black.
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TickImage(pose, size: 148, semanticLabel: 'Tick'),
            const SizedBox(height: 12),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: 24,
                color: dialOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(action),
            ),
          ],
        ),
      ),
    ),
  );
}
