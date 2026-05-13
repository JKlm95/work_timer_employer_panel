import 'package:flutter/material.dart';

import '../theme/app_layout.dart';

/// Pinned header with optional elevation when content scrolls underneath.
class AppPinnedToolbarDelegate extends SliverPersistentHeaderDelegate {
  AppPinnedToolbarDelegate({required this.child, this.extent = 52});

  final Widget child;
  final double extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: scheme.surfaceTint,
      child: SizedBox(height: extent, child: child),
    );
  }

  @override
  double get maxExtent => extent;

  @override
  double get minExtent => extent;

  @override
  bool shouldRebuild(covariant AppPinnedToolbarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.extent != extent;
  }
}

/// Hairline bottom for in-page toolbars (non-sliver).
class AppToolbarSurface extends StatelessWidget {
  const AppToolbarSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppLayout.toolbarPaddingH,
            vertical: AppLayout.toolbarPaddingV,
          ),
          child: child,
        ),
      ),
    );
  }
}
