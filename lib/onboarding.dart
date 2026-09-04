import 'package:flutter/material.dart';

import 'permissions.dart';
import 'store.dart';
import 'theme.dart';
import 'tick.dart';

/// Three screens, and one of them is a permission.
///
/// Deliberately short. Onboarding that explains a screen-time app to someone
/// who went looking for a screen-time app is time taken from the thing they
/// came for — but the two permissions genuinely need saying, because neither
/// can be granted here and both look alarming in Settings without a reason.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.store});

  final TickStore store;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) {
      widget.store.completeOnboarding();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const TickMessage(
                    pose: Tick.standing,
                    headline: 'Know your time',
                    body:
                        'Where the day actually went, app by app. Your phone '
                        'has been keeping this all along — Tick just shows '
                        'you. Nothing leaves the device, and there is no '
                        'account.',
                  ),
                  TickMessage(
                    pose: Tick.thinking,
                    headline: 'Let Tick read it',
                    body:
                        'Usage access is a switch in Settings, not a pop-up. '
                        'Without it there is nothing to show.',
                    actionLabel: store.grants.usage
                        ? 'Granted'
                        : 'Open usage access',
                    onAction: store.grants.usage
                        ? null
                        : () => openUsageAccess(context),
                  ),
                  TickMessage(
                    pose: Tick.complete,
                    headline: 'And to act on it',
                    body:
                        'To send you home when an app runs out of time, Tick '
                        'has to notice which app came to the front. That is '
                        'accessibility access. It cannot read anything inside '
                        'your apps, and you can skip it — you would still get '
                        'the numbers.',
                    actionLabel: store.grants.accessibility
                        ? 'Granted'
                        : 'Turn on enforcement',
                    onAction: store.grants.accessibility
                        ? null
                        : () => openGuardSettings(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? accentOf(context)
                                : cellEmpty(context),
                            borderRadius: BorderRadius.circular(pill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == 2 ? 'Start' : 'Next'),
                  ),
                  // Always skippable. Someone who wants to look around before
                  // granting anything gets the app with its permission cards
                  // in it, which is a better argument than this screen is.
                  if (_page < 2)
                    TextButton(
                      onPressed: store.completeOnboarding,
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
