import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_row.dart';
import 'clock.dart';
import 'duration.dart';
import 'focus_sheet.dart';
import 'limit_sheet.dart';
import 'page_bar.dart';
import 'permissions.dart';
import 'store.dart';
import 'theme.dart';
import 'tick.dart';

/// Limits: the budgets, the sessions and the schedules.
class LimitsPage extends StatelessWidget {
  const LimitsPage({super.key, required this.store});

  final TickStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Limits',
              subtitle: store.limits.isEmpty
                  ? 'Nothing is limited yet'
                  : '${plural(store.limits.length, 'app')} limited',
              actions: [
                RoundIconButton(
                  icon: LucideIcons.plus,
                  filled: true,
                  onPressed: () => showLimitSheet(context, store),
                  tooltip: 'Add a limit',
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
    final limited = store.limitedPackages;

    if (limited.isEmpty && store.schedules.isEmpty && !store.focus.active) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        children: [
          if (needsGuard(store)) ...[
            const GuardCard(),
            const SizedBox(height: 16),
          ],
          _FocusCard(store: store),
          const SizedBox(height: 24),
          TickMessage(
            pose: Tick.complete,
            headline: 'No limits yet',
            body:
                'Give an app a few minutes a day. Past that, Tick sends you '
                'back to the home screen — and you can change your mind any '
                'time.',
            actionLabel: 'Limit an app',
            onAction: () => showLimitSheet(context, store),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        if (needsGuard(store)) ...[
          const GuardCard(),
          const SizedBox(height: 12),
        ],
        _FocusCard(store: store),
        if (limited.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Daily limits', style: text.titleMedium),
          const SizedBox(height: 4),
          for (final package in limited)
            AppRow(
              store: store,
              package: package,
              ms: store.usedTodayMs(package),
              // Against its own budget, not against the busiest app: this bar
              // is how much of *this* limit is gone, which is the only thing
              // the row is about.
              fraction:
                  store.usedTodayMs(package) / (store.limits[package]! * 60000),
              trailing: _note(package),
              onTap: () => showLimitSheet(context, store, package: package),
            ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Schedules', style: text.titleMedium)),
            RoundIconButton(
              icon: LucideIcons.plus,
              size: 36,
              onPressed: () => showScheduleSheet(context, store),
              tooltip: 'Add a schedule',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (store.schedules.isEmpty)
          Text(
            'A schedule blocks apps at a time of day rather than after a '
            'number of minutes — bedtime, or working hours.',
            style: text.bodySmall,
          )
        else
          for (final schedule in store.schedules) ...[
            _ScheduleCard(store: store, schedule: schedule),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  String _note(String package) {
    final limit = store.limits[package]!;
    final used = store.usedTodayMs(package);
    if (used >= limit * 60000) {
      return 'Done for today · ${humanMinutes(limit)} used';
    }
    return '${remainingMs(used, limit)} left of ${humanMinutes(limit)}';
  }
}

/// The focus session: a countdown while one is running, an invitation when
/// none is.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.store});

  final TickStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final running = store.focus.active;

    return TintCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: chipFill(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.timer, size: 20, color: accentOf(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  running ? 'Focus session' : 'Start a focus session',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? '${humanMs(store.focus.left.inMilliseconds)} left · '
                            '${plural(store.focus.packages.length, 'app')}'
                      : 'Put a few apps away for a while.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (running)
            TextButton(onPressed: store.endFocus, child: const Text('End'))
          else
            RoundIconButton(
              icon: LucideIcons.play,
              filled: true,
              size: 36,
              onPressed: () => showFocusSheet(context, store),
              tooltip: 'Start a focus session',
            ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.store, required this.schedule});

  final TickStore store;
  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // clock(), not DateTime.now(): every other date-shaped thing in the app
    // goes through the injectable clock, and a card that read the wall clock
    // instead showed "On now" against a pinned test time — which is the same
    // bug a golden taken at 22:05 would have hidden.
    final active = schedule.activeAt(clock());
    final days = schedule.days.isEmpty || schedule.days.length == 7
        ? 'Every day'
        : ([
            ...schedule.days,
          ]..sort()).map((d) => weekdayShort[d - 1]).join(' ');

    return TintCard(
      onTap: () => showScheduleSheet(context, store, existing: schedule),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        schedule.name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      const TintChip(
                        icon: LucideIcons.check,
                        label: 'On now',
                        semanticsLabel: 'Blocking right now',
                        done: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${schedule.from}–${schedule.to} · $days · '
                  '${plural(schedule.packages.length, 'app')}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: schedule.enabled,
            onChanged: (on) =>
                store.saveSchedule(schedule.copyWith(enabled: on)),
          ),
        ],
      ),
    );
  }
}
