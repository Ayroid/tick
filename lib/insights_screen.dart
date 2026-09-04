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

/// Insights: the same numbers over a longer window.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.store});

  final TickStore store;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  Period _period = Period.week;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final span = spanOf(_period, today());
    final totals = appTotals(store, span.from, span.to);
    final total = sumOf(totals);
    final change = changeAgainstPrevious(store, span);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(title: 'Insights', subtitle: _subtitle(span)),
            if (!store.grants.usage)
              const Expanded(child: UsageGate())
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  children: [
                    Segmented<Period>(
                      options: const {
                        Period.day: 'Day',
                        Period.week: 'Week',
                        Period.month: 'Month',
                      },
                      value: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                    const SizedBox(height: 16),
                    _Summary(total: total, change: change, period: _period),
                    const SizedBox(height: 12),
                    _Bars(store: store, span: span),
                    const SizedBox(height: 24),
                    if (totals.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TickMessage(
                          pose: Tick.thinking,
                          headline: 'Nothing recorded here',
                          body:
                              'Tick keeps a daily total from the day you '
                              'installed it. Android only holds about a week '
                              'of the detail behind it, so the earliest days '
                              'may be blank.',
                        ),
                      )
                    else ...[
                      Text('By app', style: text.titleMedium),
                      const SizedBox(height: 4),
                      for (final app in ranked(totals))
                        AppRow(
                          store: store,
                          package: app.package,
                          ms: app.ms,
                          fraction: app.ms / ranked(totals).first.ms,
                          trailing: _notifications(store, span, app.package),
                        ),
                    ],
                    if (!store.grants.notifications) ...[
                      const SizedBox(height: 24),
                      const NotificationCard(),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(({DateTime from, DateTime to}) span) => switch (_period) {
    Period.day => longDate(span.from),
    Period.week =>
      '${shortDate(span.from)} – ${shortDate(shiftDays(span.to, -1))}',
    Period.month => '${months[span.from.month - 1]} ${span.from.year}',
  };

  String? _notifications(
    TickStore store,
    ({DateTime from, DateTime to}) span,
    String package,
  ) {
    if (!store.grants.notifications) return null;
    final count = notificationTotals(store, span.from, span.to)[package];
    return count == null ? null : plural(count, 'notification');
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.change,
    required this.period,
  });

  final int total;
  final double? change;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return TintCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('On screen', style: text.bodySmall),
                const SizedBox(height: 2),
                Text(
                  humanMs(total),
                  strutStyle: monoStrut(29),
                  style: mono(
                    29,
                    color: scheme.onSurface,
                    weight: FontWeight.w700,
                    spacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          if (change != null)
            TintChip(
              // Down is not praise and up is not a scolding. The arrow says
              // which way it went and the app says nothing about whether that
              // was good — a week with more screen time might have been a
              // week off.
              icon: change! < 0
                  ? LucideIcons.trendingDown
                  : LucideIcons.trendingUp,
              label: '${(change!.abs() * 100).round()}%',
              semanticsLabel:
                  '${(change!.abs() * 100).round()} percent '
                  '${change! < 0 ? 'less' : 'more'} than the '
                  '${switch (period) {
                    Period.day => 'day',
                    Period.week => 'week',
                    Period.month => 'period',
                  }} before',
            ),
        ],
      ),
    );
  }
}

/// One bar per day across the span.
class _Bars extends StatelessWidget {
  const _Bars({required this.store, required this.span});

  final TickStore store;
  final ({DateTime from, DateTime to}) span;

  @override
  Widget build(BuildContext context) {
    final series = dailySeries(store, span.from, span.to);
    final peak = series.fold(0, (best, d) => d.ms > best ? d.ms : best);
    // A month of bars is too many to label; a week is exactly right.
    final labelEvery = series.length > 10 ? 7 : 1;

    return TintCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 108,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < series.length; i++)
                  Expanded(
                    child: Semantics(
                      label:
                          '${shortDate(series[i].day)}, '
                          '${humanMs(series[i].ms)}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor: peak == 0
                                    ? 0.02
                                    : (series[i].ms / peak).clamp(0.02, 1.0),
                                // See the note in app_row.dart: an unset
                                // factor is a loose constraint, and a
                                // childless DecoratedBox under one has no
                                // size at all.
                                widthFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: series[i].ms == 0
                                        ? cellEmpty(context)
                                        : accentOf(context),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 14,
                              child: i % labelEvery == 0
                                  ? FittedBox(
                                      child: Text(
                                        weekdayShort[series[i].day.weekday - 1],
                                        strutStyle: monoStrut(10),
                                        style: mono(
                                          10,
                                          color: gridLabel(context),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            peak == 0 ? 'No days recorded yet' : 'Busiest day ${shortMs(peak)}',
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
