import 'package:flutter/material.dart';

import 'limit_sheet.dart' show AppList, SheetFrame;
import 'store.dart';
import 'theme.dart';

/// Block a set of apps for the next while.
///
/// A session is not a schedule with one date on it. It has no days, no
/// recurrence and nothing to turn off — it ends when it ends, and then it does
/// not exist. Keeping the two apart is what stops the schedule list filling up
/// with dead one-offs.
Future<void> showFocusSheet(BuildContext context, TickStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _FocusSheet(store: store),
  );
}

class _FocusSheet extends StatefulWidget {
  const _FocusSheet({required this.store});

  final TickStore store;

  @override
  State<_FocusSheet> createState() => _FocusSheetState();
}

class _FocusSheetState extends State<_FocusSheet> {
  static const _lengths = [15, 25, 45, 60, 90];

  int _minutes = 25;
  late Set<String> _packages;

  @override
  void initState() {
    super.initState();
    // The apps you already thought were worth limiting are the apps you want
    // out of the way for the next half hour. Pre-selected, and changeable.
    _packages = {...widget.store.limits.keys};
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SheetFrame(
      title: 'Focus session',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final length in _lengths)
                LengthChip(
                  minutes: length,
                  selected: length == _minutes,
                  onTap: () => setState(() => _minutes = length),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _packages.isEmpty
                ? 'Pick the apps to put away.'
                : '${plural(_packages.length, 'app')} blocked for $_minutes '
                      'minutes.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: AppList(
              store: widget.store,
              selected: _packages,
              onToggle: (p) => setState(
                () => _packages.contains(p)
                    ? _packages.remove(p)
                    : _packages.add(p),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _packages.isEmpty
                ? null
                : () {
                    widget.store.startFocus(
                      Duration(minutes: _minutes),
                      _packages,
                    );
                    Navigator.of(context).pop();
                  },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

/// Create a schedule, or edit one that exists.
Future<void> showScheduleSheet(
  BuildContext context,
  TickStore store, {
  Schedule? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ScheduleSheet(store: store, existing: existing),
  );
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.store, required this.existing});

  final TickStore store;
  final Schedule? existing;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late TextEditingController _name;
  late Set<String> _packages;
  late List<int> _days;
  late String _from;
  late String _to;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? 'Bedtime');
    _packages = {...?existing?.packages};
    _days = [...?existing?.days];
    _from = existing?.from ?? '22:00';
    _to = existing?.to ?? '07:00';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final current = (start ? _from : _to).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(current[0]) ?? 0,
        minute: int.tryParse(current[1]) ?? 0,
      ),
    );
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _from = text : _to = text);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wraps = _from.compareTo(_to) > 0;

    return SheetFrame(
      title: widget.existing == null ? 'New schedule' : 'Edit schedule',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'From',
                  value: _from,
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'To',
                  value: _to,
                  onTap: () => _pickTime(false),
                ),
              ),
            ],
          ),
          if (wraps)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                // Said out loud, because a window that ends before it starts
                // looks like a mistake until you know it is the normal case.
                'Overnight — this runs until $_to the next morning.',
                style: text.labelSmall,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 1; day <= 7; day++)
                _DayToggle(
                  day: day,
                  // No days chosen means every day, which is what the guard
                  // assumes too — so all-on and none-on look the same and mean
                  // the same.
                  selected: _days.isEmpty || _days.contains(day),
                  onTap: () => setState(() {
                    if (_days.isEmpty) {
                      _days = [
                        for (var d = 1; d <= 7; d++)
                          if (d != day) d,
                      ];
                    } else if (_days.contains(day)) {
                      _days.remove(day);
                    } else {
                      _days.add(day);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: AppList(
              store: widget.store,
              selected: _packages,
              onToggle: (p) => setState(
                () => _packages.contains(p)
                    ? _packages.remove(p)
                    : _packages.add(p),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _packages.isEmpty
                ? null
                : () {
                    widget.store.saveSchedule(
                      Schedule(
                        id: widget.existing?.id ?? newId(),
                        name: _name.text.trim().isEmpty
                            ? 'Schedule'
                            : _name.text.trim(),
                        packages: _packages,
                        days: _days,
                        from: _from,
                        to: _to,
                        enabled: widget.existing?.enabled ?? true,
                      ),
                    );
                    Navigator.of(context).pop();
                  },
            child: const Text('Save schedule'),
          ),
          if (widget.existing != null)
            TextButton(
              onPressed: () async {
                final confirmed = await _confirmDelete(context);
                if (!context.mounted || !confirmed) return;
                widget.store.removeSchedule(widget.existing!.id);
                Navigator.of(context).pop();
              },
              child: const Text('Delete schedule'),
            ),
        ],
      ),
    );
  }
}

/// The one place red appears in this app.
Future<bool> _confirmDelete(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        barrierColor: navy.withValues(alpha: 0.32),
        builder: (context) => AlertDialog(
          title: const Text('Delete this schedule?'),
          content: const Text('The apps in it stop being blocked at once.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(
                value,
                strutStyle: monoStrut(15),
                style: mono(
                  15,
                  color: scheme.onSurface,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: weekdays[day - 1],
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? accentOf(context)
                  : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              weekdayShort[day - 1],
              strutStyle: monoStrut(11),
              style: mono(
                11,
                color: selected ? onAccent(context) : scheme.secondary,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A focus-session length. Shares nothing with the limit sheet's preset chip
/// but its shape, and duplicating twenty lines beats a `Chip` widget with four
/// flags on it.
class LengthChip extends StatelessWidget {
  const LengthChip({
    super.key,
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$minutes minutes',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? accentOf(context)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(pill),
          ),
          child: Text(
            '${minutes}m',
            strutStyle: monoStrut(13),
            style: mono(
              13,
              color: selected ? onAccent(context) : scheme.onSurface,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
