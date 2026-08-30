import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Figma design reference canvas (iPhone frames, logical points).
const double kDesignWidth = 393;
const double kDesignHeight = 852;

/// Tablet breakpoint on the shortest screen side (Android/iOS guidance).
const double kTabletBreakpoint = 600;

/// Responsive sizing system.
///
/// Every screen is authored against [kDesignWidth]; at runtime each design
/// pixel is multiplied by a clamped scale factor so layouts:
///  * shrink gently on small Android phones (360dp),
///  * render 1:1 on reference-size iPhones,
///  * grow only up to a comfortable cap on large phones,
///  * stop inflating typography on tablets — content is centered with a
///    max width instead ([contentMaxWidth]).
extension ResponsiveContext on BuildContext {
  Size get _size => MediaQuery.sizeOf(this);

  double get screenWidth => _size.width;

  double get screenHeight => _size.height;

  /// True when the shortest side is tablet-class (iPad, tablets, folds).
  bool get isTablet =>
      math.min(_size.width, _size.height) >= kTabletBreakpoint;

  bool get isPhone => !isTablet;

  bool get isLandscape => _size.width > _size.height;

  /// Uniform design-pixel scale factor.
  ///
  /// Clamped so extreme aspect ratios never produce unreadable or absurd
  /// sizes. Tablets are capped lower because they center content rather
  /// than stretching it edge to edge.
  double get designScale {
    final raw = _size.width / kDesignWidth;
    if (isTablet) return raw.clamp(1.0, 1.15);
    return raw.clamp(0.85, 1.25);
  }

  /// Scales a size/spacing/typography value from the Figma canvas.
  double rs(num designPx) => designPx * designScale;

  /// Scaled font size (same factor; kept separate for readability).
  double rsFont(num designPx) => designPx * designScale;

  /// Maximum width for form/list content: full width on phones,
  /// comfortably constrained and centered on tablets.
  double get contentMaxWidth => isTablet ? 560.0 : double.infinity;

  /// Horizontal page padding scaled from the design's 24px gutter.
  double get pagePadding => rs(24);

  /// Wraps [child] so it is centered and capped at [contentMaxWidth]
  /// with the standard scaled horizontal padding.
  Widget centerContent(Widget child) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: child,
        ),
      );
}
