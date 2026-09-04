import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'analytics.dart';
import 'app_row.dart';
import 'duration.dart';
import 'page_bar.dart';
import 'permissions.dart';
import 'store.dart';
import 'theme.dart';
import 'tick.dart';

/// Today: what the day has looked like so far.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.onSettings});

  final TickStore store;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: greeting(),
              subtitle: longDate(today()),
              actions: [
                RoundIconButton(
                  icon: LucideIcons.settings,
                  onPressed: onSettings,
                  tooltip: 'Settings',
                ),
              ],
            ),
            Expanded(
              child: store.grants.usage
                  ? _Body(store: store)
                  : const UsageGate(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.store});

  final TickStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final apps = store.todayUsage.ranked;
    final busiest = apps.isEmpty ? 0 : apps.first.ms;

    return ListView(
      // Clear of the floating tab pill, which is not a bottomNavigationBar and
      // so reserves no space of its own.
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        _Hero(store: store),
        if (needsGuard(store)) ...[
          const SizedBox(height: 12),
          const GuardCard(),
        ],
        const SizedBox(height: 24),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: TickMessage(
              pose: Tick.rest,
              headline: 'Nothing yet today',
              body:
                  'Whatever you pick up first will show here. There is no '
                  'wrong number — the point is knowing it.',
            ),
          )
        else ...[
          Text('Most used today', style: text.titleMedium),
          const SizedBox(height: 4),
          for (final app in apps)
            AppRow(
              store: store,
              package: app.package,
              ms: app.ms,
              fraction: busiest == 0 ? 0 : app.ms / busiest,
              trailing: _note(app.package, app.opens),
            ),
        ],
      ],
    );
  }

  /// The line under an app's bar: why it is blocked, or how often it was
  /// picked up. Never both — a blocked app's open count is the least
  /// interesting thing about it.
  String? _note(String package, int opens) {
    final blocked = store.blockReason(package);
    if (blocked != null) return '$blocked · done for today';
    final limit = store.limits[package];
    if (limit != null) {
      return '${remainingMs(store.usedTodayMs(package), limit)} left of '
          '${humanMinutes(limit)}';
    }
    return opens > 0 ? plural(opens, 'open') : null;
  }
}

/// The day's total, with the budget ring around it when there is a budget.
class _Hero extends StatelessWidget {
  const _Hero({required this.store});

  final TickStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = store.todayUsage.totalMs;
    final budget = budgetToday(store);
    // Over the budget the ring is simply full; the caption carries the
    // overshoot. A ring that wrapped a second time would read as less time.
    final spent = budget == null ? 0.0 : budget.used / budget.budget;

    return TintCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        children: [
          SizedBox(
            height: 168,
            width: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // No limits set means no budget, and a ring with nothing to
                // fill it is a decoration pretending to be a measurement. The
                // track alone still frames the number.
                CustomPaint(
                  size: const Size.square(168),
                  painter: _RingPainter(
                    fraction: spent,
                    track: cellEmpty(context),
                    fill: accentOf(context),
                    done: goldOf(context),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      humanMs(total),
                      strutStyle: monoStrut(30),
                      style: mono(
                        30,
                        color: Theme.of(context).colorScheme.onSurface,
                        weight: FontWeight.w700,
                        spacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // The big number is the whole day; this line is the
                      // ring, and says which numbers the ring is drawing.
                      budget == null
                          ? 'on screen'
                          : '${humanMs(budget.used)} of '
                                '${humanMs(budget.budget)} limited',
                      style: text.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TintChip(
                icon: LucideIcons.smartphone,
                label: '${store.todayUsage.unlocks}',
                semanticsLabel:
                    '${plural(store.todayUsage.unlocks, 'unlock')} today',
                dim: store.todayUsage.unlocks == 0,
              ),
              const SizedBox(width: 8),
              TintChip(
                icon: LucideIcons.layoutGrid,
                label: '${store.todayUsage.byPackage.length}',
                semanticsLabel:
                    '${plural(store.todayUsage.byPackage.length, 'app')} used',
                dim: store.todayUsage.byPackage.isEmpty,
              ),
              if (budget != null && spent >= 1) ...[
                const SizedBox(width: 8),
                const TintChip(
                  icon: LucideIcons.check,
                  label: 'Done',
                  semanticsLabel: 'Budget spent for today',
                  done: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.done,
  });

  final double fraction;
  final Color track;
  final Color fill;

  /// Where the ring lands once the budget is spent. Gold, because an app that
  /// has used its time is finished for the day — not failed. Legible here only
  /// because it sits against the track rather than against the page.
  final Color done;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.075;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );

    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      // Past the budget the ring is simply full. The percentage under it
      // carries the overshoot, which is the honest place for it — a ring that
      // wrapped a second time would read as less time, not more.
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fraction >= 1 ? done : fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
