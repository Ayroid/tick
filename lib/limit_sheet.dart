import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_row.dart';
import 'duration.dart';
import 'store.dart';
import 'theme.dart';

/// Give an app a daily budget, or change the one it has.
///
/// Two steps in one sheet rather than two sheets: picking the app and setting
/// its minutes are one decision, and a picker that dismisses itself only to
/// have another slide up reads as the app losing its place.
Future<void> showLimitSheet(
  BuildContext context,
  TickStore store, {
  String? package,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LimitSheet(store: store, package: package),
  );
}

class _LimitSheet extends StatefulWidget {
  const _LimitSheet({required this.store, required this.package});

  final TickStore store;
  final String? package;

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  String? _package;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    _package = widget.package;
    _minutes = _package == null ? 30 : (widget.store.limits[_package] ?? 30);
  }

  @override
  Widget build(BuildContext context) {
    final package = _package;
    return SheetFrame(
      title: package == null ? 'Which app?' : widget.store.labelOf(package),
      child: package == null
          ? AppList(
              store: widget.store,
              onPick: (picked) => setState(() {
                _package = picked;
                _minutes = widget.store.limits[picked] ?? 30;
              }),
              noteFor: (p) {
                final limit = widget.store.limits[p];
                return limit == null ? null : '${humanMinutes(limit)} a day';
              },
            )
          : _Minutes(
              store: widget.store,
              package: package,
              minutes: _minutes,
              onChanged: (m) => setState(() => _minutes = m),
              onSave: () {
                widget.store.setLimit(package, _minutes);
                Navigator.of(context).pop();
              },
              onRemove: widget.store.limits.containsKey(package)
                  ? () {
                      widget.store.setLimit(package, null);
                      Navigator.of(context).pop();
                    }
                  : null,
            ),
    );
  }
}

class _Minutes extends StatelessWidget {
  const _Minutes({
    required this.store,
    required this.package,
    required this.minutes,
    required this.onChanged,
    required this.onSave,
    required this.onRemove,
  });

  final TickStore store;
  final String package;
  final int minutes;
  final ValueChanged<int> onChanged;
  final VoidCallback onSave;
  final VoidCallback? onRemove;

  /// The budgets people actually pick. A slider alone makes 30 minutes a
  /// fiddly target; presets alone cannot say 20.
  static const _presets = [10, 15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final used = store.usedTodayMs(package);

    // Scrollable, because this column is genuinely taller than a small phone
    // once the presets wrap onto two rows — and taller again for anyone who
    // has scaled their text up. A sheet that clips its own Save button is
    // worse than one you have to nudge.
    // The choosing scrolls; the deciding does not. This column is genuinely
    // taller than a small phone once the presets wrap onto two rows, and
    // taller again for anyone who has scaled their text up — but a primary
    // action you have to go looking for is not a primary action, so Save
    // stays pinned below the scroll rather than inside it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppIcon(store: store, package: package, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            humanMinutes(minutes),
                            style: text.headlineLarge,
                          ),
                          Text('a day', style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: minutes.toDouble(),
                  min: 5,
                  max: 240,
                  // Five-minute steps: nobody sets a limit of 37 minutes, and
                  // the divisions give the slider detents to land on.
                  divisions: 47,
                  label: humanMinutes(minutes),
                  onChanged: (v) => onChanged(v.round()),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _presets)
                      _Preset(
                        minutes: preset,
                        selected: preset == minutes,
                        onTap: () => onChanged(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (used > 0)
                  Text(
                    used >= minutes * 60000
                        ? 'Already past this today — ${humanMs(used)} so far. '
                              'It will block until midnight.'
                        : '${humanMs(used)} used today, '
                              '${remainingMs(used, minutes)} would be left.',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onSave, child: const Text('Save limit')),
        if (onRemove != null)
          TextButton(onPressed: onRemove, child: const Text('Remove limit')),
      ],
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({
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
      label: humanMinutes(minutes),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? accentOf(context)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(pill),
          ),
          child: Text(
            humanMinutes(minutes),
            strutStyle: monoStrut(13),
            style: mono(
              13,
              color: selected ? onAccent(context) : scheme.onSurface,
              // Weight as well as colour, so the selection is legible without
              // relying on colour alone.
              weight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The shape every sheet in Tick takes: page ground, a handle, a title, and
/// whatever is being edited under it.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        // The keyboard, when a sheet has a field in it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every installed app, filtered as you type.
///
/// Shared by the limit sheet, the focus sheet and the schedule sheet — the
/// three places in the app where the question is "which apps?".
class AppList extends StatefulWidget {
  const AppList({
    super.key,
    required this.store,
    this.onPick,
    this.selected,
    this.onToggle,
    this.noteFor,
  });

  final TickStore store;

  /// Single-select: tap a row and the list is done with.
  final ValueChanged<String>? onPick;

  /// Multi-select: a checkbox per row, and the caller owns the set.
  final Set<String>? selected;
  final ValueChanged<String>? onToggle;

  /// An optional line under a row — an existing limit, a time.
  final String? Function(String package)? noteFor;

  @override
  State<AppList> createState() => _AppListState();
}

class _AppListState extends State<AppList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final query = _query.trim().toLowerCase();

    // Most-used first, because the app you want to limit is almost always one
    // you have been using. Alphabetical would bury it under everything whose
    // name starts with A.
    final ranked = widget.store.todayUsage.ranked.map((a) => a.package);
    final packages =
        <String>{
          ...ranked.where(widget.store.apps.containsKey),
          ...widget.store.apps.keys,
        }.where((p) {
          if (query.isEmpty) return true;
          return widget.store.labelOf(p).toLowerCase().contains(query);
        }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search apps',
            prefixIcon: Icon(LucideIcons.search, size: 18),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: packages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    widget.store.apps.isEmpty
                        ? 'Tick cannot see your apps yet.'
                        : 'No app called "$_query".',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: packages.length,
                  itemBuilder: (context, i) {
                    final package = packages[i];
                    final checked = widget.selected?.contains(package);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AppIcon(store: widget.store, package: package),
                      title: Text(
                        widget.store.labelOf(package),
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: switch (widget.noteFor?.call(package)) {
                        final note? => Text(note, style: text.labelSmall),
                        _ => null,
                      },
                      trailing: checked == null
                          ? null
                          : Checkbox(
                              value: checked,
                              onChanged: (_) => widget.onToggle?.call(package),
                            ),
                      onTap: () {
                        // Single-select and multi-select are the same list
                        // with a different callback; whichever the caller
                        // supplied is the one that runs.
                        widget.onPick?.call(package);
                        widget.onToggle?.call(package);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
