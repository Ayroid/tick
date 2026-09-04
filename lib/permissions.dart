import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'store.dart';
import 'theme.dart';
import 'tick.dart';
import 'usage.dart';

/// The three things Tick has to be given, and the screens that ask for them.
///
/// None of the three can be granted from inside the app: they are all toggles
/// on a Settings page that has to be opened and tapped by hand. So every one
/// of these is the same shape — say what it is for, open the right screen, and
/// pick the answer back up when the app resumes.

/// Open a Settings screen, and say so if the phone hasn't got one.
///
/// Some vendor ROMs ship without one of these pages. A button that silently
/// does nothing reads as a broken app; a line saying the screen isn't there at
/// least tells you to go looking.
Future<void> _open(
  BuildContext context,
  Future<bool> Function() open,
  String what,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (await open()) return;
  messenger.showSnackBar(
    SnackBar(content: Text("This phone has no $what screen to open.")),
  );
}

Future<void> openUsageAccess(BuildContext context) =>
    _open(context, Native.openUsageSettings, 'usage access');

Future<void> openGuardSettings(BuildContext context) =>
    _open(context, Native.openAccessibilitySettings, 'accessibility');

Future<void> openNotificationAccess(BuildContext context) =>
    _open(context, Native.openNotificationSettings, 'notification access');

/// What a screen shows instead of itself when there is nothing to show.
///
/// Usage access is the one permission Tick cannot work around: without it the
/// system hands back nothing at all, and there is no partial version of the
/// app to fall back to.
class UsageGate extends StatelessWidget {
  const UsageGate({super.key});

  @override
  Widget build(BuildContext context) {
    return TickMessage(
      pose: Tick.thinking,
      headline: 'Tick needs to see your screen time',
      body:
          'Android already keeps this — how long each app has been in front of '
          'you, going back months. Tick just reads it. Nothing leaves the '
          'phone.',
      actionLabel: 'Open usage access',
      onAction: () => openUsageAccess(context),
    );
  }
}

/// An inline card asking for something the screen can manage without.
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return TintCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: chipFill(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentOf(context)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: text.bodySmall),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

/// Shown on Limits when rules exist but nothing is enforcing them.
///
/// The important case, and the reason this is a card rather than a line in
/// Settings: a limit that is recorded but not enforced looks exactly like one
/// that works until the moment it doesn't.
class GuardCard extends StatelessWidget {
  const GuardCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionCard(
      icon: LucideIcons.shieldOff,
      title: 'Limits are not being enforced',
      body:
          'Tick needs accessibility access to notice when an app comes to the '
          'front. Without it your limits are recorded, but nothing happens '
          'when you pass one. Tick cannot read anything inside your apps.',
      action: 'Turn on enforcement',
      onAction: () => openGuardSettings(context),
    );
  }
}

/// Shown on Insights. The one genuinely optional permission.
class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionCard(
      icon: LucideIcons.bell,
      title: 'Count notifications too',
      body:
          'Android will not tell an app how many notifications another app '
          'sent, so this needs notification access. It only counts from the '
          'day you turn it on — there is no history to fill in.',
      action: 'Turn on counting',
      onAction: () => openNotificationAccess(context),
    );
  }
}

/// Whether the guard card belongs on screen: there are rules, and nothing is
/// enforcing them. No rules yet means nothing to warn about.
bool needsGuard(TickStore store) =>
    !store.grants.accessibility &&
    (store.limits.isNotEmpty ||
        store.schedules.isNotEmpty ||
        store.focus.active);
