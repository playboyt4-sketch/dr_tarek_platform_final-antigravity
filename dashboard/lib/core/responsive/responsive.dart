import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Viewport tiers for the Web Admin Dashboard.
enum DashboardBreakpoint { mobile, tablet, desktop }

/// Shared breakpoints for the Dashboard/Web experience. All responsive
/// decisions on this app go through these constants — no scattered
/// MediaQuery width checks inside widgets.
abstract final class AppBreakpoints {
  /// Mobile: width < 768px.
  static const double mobileMax = 768;

  /// Tablet: 768px <= width <= 1100px; Desktop: width > 1100px.
  static const double desktopMin = 1100;

  /// Legacy aliases preserved for backward compatibility.
  static const double compact = 768;
  static const double expanded = 1100;

  /// Reference Figma frame width for proportional dialog/font helpers.
  static const double figmaFrameWidth = 1280;

  /// Reference Figma frame height for reference calculations.
  static const double figmaFrameHeight = 800;
}

/// Resolves the active [DashboardBreakpoint] for a given layout [width].
DashboardBreakpoint breakpointForWidth(double width) {
  if (width < AppBreakpoints.mobileMax) return DashboardBreakpoint.mobile;
  if (width <= AppBreakpoints.desktopMin) return DashboardBreakpoint.tablet;
  return DashboardBreakpoint.desktop;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  DashboardBreakpoint get dashboardBreakpoint =>
      breakpointForWidth(screenWidth);

  bool get isMobileViewport => screenWidth < AppBreakpoints.mobileMax;
  bool get isTabletViewport =>
      screenWidth >= AppBreakpoints.mobileMax &&
      screenWidth <= AppBreakpoints.desktopMin;
  bool get isDesktopViewport => screenWidth > AppBreakpoints.desktopMin;

  bool get isCompact => isMobileViewport;
  bool get isExpanded => isDesktopViewport;

  /// Horizontal page gutter adapted to the active breakpoint.
  double get dashboardHorizontalPadding {
    return switch (dashboardBreakpoint) {
      DashboardBreakpoint.mobile => 16,
      DashboardBreakpoint.tablet => 28,
      DashboardBreakpoint.desktop => 48,
    };
  }

  /// Scales a Figma-reference px value proportionally with viewport width,
  /// clamped so typography never becomes unreadably small or oversized.
  double rs(num designPx, {double minScale = 0.65, double maxScale = 1.15}) {
    final double scale =
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

/// Shared responsive brand header for dashboard screens.
///
/// On Mobile (`< 768px`) the [DashboardShell] renders the brand and menu button
/// inside its `AppBar`, so this widget collapses to a small top spacer.
/// On Tablet/Desktop (`>= 768px`) it renders the centered brand lockup with
/// symmetric horizontal clearance for the shell's floating menu button.
class ResponsiveScreenHeader extends StatelessWidget {
  final Color lightColor;

  const ResponsiveScreenHeader({
    super.key,
    this.lightColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : context.screenWidth;
        if (width < AppBreakpoints.mobileMax) {
          return const SizedBox(height: 8);
        }
        final double sideClearance =
            width > AppBreakpoints.desktopMin ? 104 : 88;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: sideClearance),
          child: SizedBox(
            height: 72,
            width: double.infinity,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      TextSpan(
                        text: 'Tarek el araby ',
                        style: AppTypography.homeBrandHeavy(fontSize: 44),
                      ),
                      TextSpan(
                        text: 'Platform',
                        style: AppTypography.homeBrandLight(fontSize: 44)
                            .copyWith(color: lightColor),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wraps wide data tables so they expand to fill the full available width on
/// desktop, while becoming horizontally scrollable on mobile and narrow tablets.
class ResponsiveHorizontalTable extends StatelessWidget {
  final double minTableWidth;
  final Widget child;

  const ResponsiveHorizontalTable({
    super.key,
    required this.minTableWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableWidth;
        final double tableWidth = math.max(available, minTableWidth);
        if (available >= minTableWidth) {
          return SizedBox(width: tableWidth, child: child);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: tableWidth, child: child),
        );
      },
    );
  }
}
