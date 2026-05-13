import 'package:flutter/material.dart';

/// Spacing and radii shared across employer panel screens (visual refinement only).
abstract final class AppLayout {
  static const double pagePadding = 24;
  static const double pagePaddingCompact = 16;
  static const double sectionGap = 28;
  static const double blockGap = 16;
  static const double cardPadding = 20;
  static const double toolbarPaddingV = 10;
  static const double toolbarPaddingH = 16;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double iconTile = 40;

  static BorderSide outlineSide(ColorScheme scheme) =>
      BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65));
}
