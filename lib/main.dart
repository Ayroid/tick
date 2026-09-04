import 'package:flutter/material.dart';

import 'home.dart';
import 'insights_screen.dart';
import 'limits_screen.dart';
import 'onboarding.dart';
import 'page_bar.dart';
import 'settings.dart';
import 'store.dart';
import 'theme.dart';
import 'tick.dart';

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final store = TickStore();

  /// Only the parts of the store that decide what the MaterialApp renders.
  ///
  /// Rebuilding the whole app on every store notification would repaint three
  /// pages of cards every time a second of usage ticks over. This rebuilds
  /// when the shell actually changes and lets each page listen for itself.
  ///
  /// Assigned in initState rather than declared `late var ... = (...)`. A late
  /// initializer runs on first *read*, which is inside `_onStoreChanged` —
  /// i.e. after loading already finished. It would capture the post-load
  /// values, compare them equal to themselves, and never rebuild, leaving the
  /// app on its launch frame forever. Pinned by a test.
  late (ThemeMode, bool, bool) _shell;

  @override
  void initState() {
    super.initState();
    _shell = (store.themeMode, store.loaded, store.onboarded);
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStoreChanged);
    store.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Everything Tick shows belongs to the system and changes while the app is
    // in the background: the usage itself, obviously, but also all three
    // permissions, which are toggles on a Settings page the user has just been
    // sent to. Coming back to a stale screen would have Tick claiming to
    // enforce limits it can no longer enforce.
    if (state == AppLifecycleState.resumed && store.loaded) store.refresh();
  }

  void _onStoreChanged() {
    final next = (store.themeMode, store.loaded, store.onboarded);
    if (next != _shell) setState(() => _shell = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tick',
      debugShowCheckedModeBanner: false,
      theme: appTheme(dark: false),
      darkTheme: appTheme(dark: true),
      themeMode: store.themeMode,
      home: !store.loaded
          ? const LaunchFrame()
          : store.onboarded
          ? RootScreen(store: store)
          : OnboardingScreen(store: store),
    );
  }
}

/// What fills the gap between the system splash and the first real frame.
///
/// The same mark on the same ground the system splash used, so the handoff is
/// invisible rather than a flash of empty scaffold. Falls back to the drawn
/// clock, which is what runs before the art has been dropped in — and which
/// also means this frame renders in a fresh checkout with no assets at all.
class LaunchFrame extends StatelessWidget {
  const LaunchFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          'assets/splash/tick_mark.png',
          height: 148,
          fit: BoxFit.fitHeight,
          semanticLabel: 'Tick',
          errorBuilder: (context, _, _) =>
              const ClockMark(size: 128, semanticLabel: 'Tick'),
        ),
      ),
    );
  }
}

/// The shell: three swipeable pages under a floating tab pill.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key, required this.store});

  final TickStore store;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _pages = PageController();

  /// The PageView's fractional offset, as a ValueNotifier rather than
  /// setState: a swipe then repaints only the tab pill, not three pages full
  /// of cards and a chart.
  final _position = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      // `page` is pixels / viewportDimension, which is 0/0 — NaN — until the
      // PageView has been laid out once. NaN then flows into the tab weights,
      // and Dart's `clamp` propagates NaN rather than clamping it, so the pill
      // lays out at a nonsense width. Hold the last good value instead.
      final page = _pages.hasClients ? _pages.page : null;
      if (page != null && !page.isNaN) _position.value = page;
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Stack(
        children: [
          PageView(
            controller: _pages,
            children: [
              HomePage(
                store: widget.store,
                onSettings: () => openSettings(context, widget.store),
              ),
              LimitsPage(store: widget.store),
              InsightsPage(store: widget.store),
            ],
          ),
          PageTabs(
            position: _position,
            onSelect: (i) => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }
}
