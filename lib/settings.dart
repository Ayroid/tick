import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'permissions.dart';
import 'store.dart';
import 'theme.dart';

Future<void> openSettings(BuildContext context, TickStore store) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (context) => _SettingsScreen(store: store)),
  );
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.store});

  final TickStore store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Appearance', style: text.titleMedium),
            const SizedBox(height: 8),
            Segmented<ThemeMode>(
              options: const {
                ThemeMode.light: 'Light',
                ThemeMode.dark: 'Dark',
                ThemeMode.system: 'System',
              },
              value: store.themeMode,
              onChanged: store.setThemeMode,
            ),
            const SizedBox(height: 24),
            Text('Access', style: text.titleMedium),
            const SizedBox(height: 8),
            _GrantRow(
              icon: LucideIcons.chartNoAxesColumn,
              label: 'Usage access',
              detail: 'Reads how long each app has been in front of you.',
              granted: store.grants.usage,
              onTap: () => openUsageAccess(context),
            ),
            _GrantRow(
              icon: LucideIcons.shield,
              label: 'Enforcement',
              detail: 'Notices which app came to the front, so limits work.',
              granted: store.grants.accessibility,
              onTap: () => openGuardSettings(context),
            ),
            _GrantRow(
              icon: LucideIcons.bell,
              label: 'Notification counts',
              detail: 'Optional. Counts forward from the day you turn it on.',
              granted: store.grants.notifications,
              onTap: () => openNotificationAccess(context),
            ),
            const SizedBox(height: 24),
            Text('Backup', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Your limits, schedules and the daily totals Tick has kept. Not '
              'your screen time itself — that belongs to Android, and a new '
              'phone has its own.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _export(context, store),
              child: const Text('Export a backup'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _import(context, store),
              child: const Text('Restore from a file'),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Tick · everything stays on this phone',
                style: text.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _export(BuildContext context, TickStore store) async {
  final dir = await Directory.systemTemp.createTemp('tick');
  final file = File('${dir.path}/tick-${dayKey(today())}.json');
  await file.writeAsString(store.exportJson());
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: 'Tick backup'),
  );
}

Future<void> _import(BuildContext context, TickStore store) async {
  final picked = await FilePicker.pickFile(dialogTitle: 'Choose a Tick backup');
  if (picked == null || !context.mounted) return;

  // Decoded as UTF-8 rather than with String.fromCharCodes: an app label can
  // be in any script, and the wrong decoder turns them into mojibake that then
  // gets saved back.
  final raw = utf8.decode(await picked.readAsBytes());
  if (!context.mounted) return;

  final replace = await showDialog<bool>(
    context: context,
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => AlertDialog(
      title: const Text('Replace everything?'),
      content: const Text(
        'Your current limits, schedules and history are swapped for what is '
        'in this file.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (replace != true || !context.mounted) return;

  if (!store.importJson(raw)) {
    await showDialog<void>(
      context: context,
      barrierColor: navy.withValues(alpha: 0.32),
      builder: (context) => AlertDialog(
        title: const Text('That file could not be read'),
        content: const Text(
          'Nothing was changed. It may not be a Tick backup.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.granted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool granted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TintCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: accentOf(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(detail, style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Words, not a green dot: the state matters and colour is never
            // the only thing carrying it.
            TintChip(
              icon: granted ? LucideIcons.check : LucideIcons.x,
              label: granted ? 'On' : 'Off',
              semanticsLabel: granted ? '$label is on' : '$label is off',
              dim: !granted,
              done: granted,
            ),
          ],
        ),
      ),
    );
  }
}
