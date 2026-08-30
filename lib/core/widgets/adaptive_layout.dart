import 'package:flutter/material.dart';
import '../responsive/responsive.dart';

/// A responsive layout wrapper that adapts to the parent's constraints.
/// On phones, it allows the content to scroll if it exceeds the vertical height.
/// On tablets/desktops, it applies a max-width and can optionally switch 
/// to a side-by-side or grid layout for larger viewports, instead of just 
/// artificially scaling up a mobile layout.
class AdaptiveLayout extends StatelessWidget {
  final WidgetBuilder mobileBuilder;
  final WidgetBuilder? tabletBuilder;
  final double maxWidth;

  const AdaptiveLayout({
    super.key,
    required this.mobileBuilder,
    this.tabletBuilder,
    this.maxWidth = 800.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = context.isTablet || constraints.maxWidth >= 600;

        if (isTablet && tabletBuilder != null) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: tabletBuilder!(context),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? maxWidth : double.infinity),
            child: mobileBuilder(context),
          ),
        );
      },
    );
  }
}

/// A container that preserves a specific design aspect ratio
/// and scales its contents using LayoutBuilder constraints rather than 
/// blindly relying on screen width.
class AdaptiveAspectContainer extends StatelessWidget {
  final double designWidth;
  final double designHeight;
  final Widget Function(BuildContext context, BoxConstraints constraints, double scale) builder;

  const AdaptiveAspectContainer({
    super.key,
    required this.designWidth,
    required this.designHeight,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: designWidth / designHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate scale based on the local constraints width vs design width.
          final scale = constraints.maxWidth / designWidth;
          return builder(context, constraints, scale);
        },
      ),
    );
  }
}
