import 'package:flutter/material.dart';

/// Shared breakpoints for the Dashboard/Web experience. All responsive
/// decisions on this app go through these constants — no scattered
/// MediaQuery width checks inside widgets.
abstract final class AppBreakpoints {
  /// Below this the layout behaves like a narrow/phone web viewport.
  static const double compact = 600;

  /// At or above this the full desktop composition is used.
  static const double expanded = 1024;

  /// Reference Figma frame width for the dashboard login design.
  static const double figmaFrameWidth = 1440;

  /// Reference Figma frame height for the dashboard login design.
  static const double figmaFrameHeight = 1024;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isCompact => screenWidth < AppBreakpoints.compact;
  bool get isExpanded => screenWidth >= AppBreakpoints.expanded;

  /// Scales a Figma-reference px value proportionally with viewport width,
  /// clamped so typography never becomes unreadably small or oversized.
  double rs(num designPx, {double minScale = 0.45, double maxScale = 1.15}) {
    final scale =
        (screenWidth / AppBreakpoints.figmaFrameWidth).clamp(minScale, maxScale);
    return designPx * scale;
  }
}

/// Centers [child] horizontally and constrains it to [maxWidth].
class ResponsiveCenter extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const ResponsiveCenter({
    super.key,
    this.maxWidth = 620,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
