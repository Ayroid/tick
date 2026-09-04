import 'package:flutter/material.dart';

import 'duration.dart';
import 'store.dart';
import 'theme.dart';

/// One app's launcher icon, or something recognisable when there isn't one.
///
/// An app can be uninstalled while its time stays in the archive, so this has
/// to render for a package that no longer exists. The initial on a tinted
/// square is not a placeholder for a missing image — it is what that app looks
/// like now.
class AppIcon extends StatelessWidget {
  const AppIcon({
    super.key,
    required this.store,
    required this.package,
    this.size = 38,
  });

  final TickStore store;
  final String package;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = store.apps[package]?.icon;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          // A package whose icon bytes are corrupt should cost one row, not
          // the screen.
          errorBuilder: (context, _, _) =>
              _Initial(label: store.labelOf(package), size: size),
        ),
      );
    }
    return _Initial(label: store.labelOf(package), size: size);
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chipFill(context),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// An app, its time, and how much of the screen's total that was.
///
/// The bar is proportion, not an absolute scale, so a quiet day still fills
/// the row rather than rendering five invisible slivers. The duration beside
/// it is the number that means something, which is why the bar is allowed to
/// be relative.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.store,
    required this.package,
    required this.ms,
    required this.fraction,
    this.trailing,
    this.onTap,
  });

  final TickStore store;
  final String package;
  final int ms;

  /// 0 to 1, against the busiest app in the same list.
  final double fraction;

  /// A note under the label — a limit, a block reason, a notification count.
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = store.labelOf(package);
    final duration = humanMs(ms);

    return Semantics(
      button: onTap != null,
      // One announcement per row instead of four stops. The bar carries no
      // words of its own, so nothing is lost by excluding the children.
      label: [label, duration, ?trailing].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Row(
              children: [
                AppIcon(store: store, package: package),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            duration,
                            strutStyle: monoStrut(13),
                            style: mono(
                              13,
                              color: Theme.of(context).colorScheme.onSurface,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      _Bar(fraction: fraction),
                      if (trailing != null) ...[
                        const SizedBox(height: 5),
                        Text(trailing!, style: text.labelSmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(pill),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: cellEmpty(context))),
            FractionallySizedBox(
              // A row that is on the list at all gets a visible sliver: a bar
              // rounded to nothing reads as an empty row rather than a short
              // one.
              widthFactor: fraction.isNaN ? 0.02 : fraction.clamp(0.02, 1.0),
              // heightFactor as well, and not because the bar needs scaling.
              // A factor that is left null passes a LOOSE constraint on that
              // axis, and a DecoratedBox with no child collapses to zero
              // there — so the fill vanished and only the track was ever
              // drawn. Caught by the goldens; invisible in a widget test,
              // which finds the widget whatever size it rendered at.
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: accentOf(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
