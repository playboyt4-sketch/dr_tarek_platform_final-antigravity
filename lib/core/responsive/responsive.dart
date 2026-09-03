import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Figma design reference canvas (iPhone frames, logical points).
const double kDesignWidth = 393;
const double kDesignHeight = 852;

/// Tablet breakpoint on the shortest screen side (Android/iOS guidance).
const double kTabletBreakpoint = 600;

/// Responsive sizing system.
///
/// This system provides THREE distinct scaling mechanisms:
///
/// 1. **Horizontal Scale** ([textScale]) — scales horizontal dimensions:
///    font sizes, horizontal padding, horizontal gaps, border radius.
///    Based on viewport width, clamped for readability.
///
/// 2. **Vertical Scale** ([heightScale]) — scales vertical dimensions:
///    vertical spacing, vertical padding, vertical gaps, component heights.
///    Based on viewport height, clamped for readability.
///
/// 3. **Component Layout** — uses [LayoutBuilder] / [ConstrainedBox] / [AspectRatio]
///    so components size themselves to their PARENT CONSTRAINTS, not global viewport.
///
/// Screens should:
/// - Wrap content in [ResponsiveScreen] or [AdaptiveLayout] for correct tablet/phone behavior
/// - Use [AdaptiveAspectContainer] for hero images/illustrations
/// - Use [textScale] (via [rsFont]) for typography
/// - Use [spacingScale] (via [rs]) for horizontal spacing/padding/radius
/// - Use [heightScale] (via [rsV]) for vertical spacing/padding/heights
/// - AVOID using global scale for fixed component widths/heights
extension ResponsiveContext on BuildContext {
  Size get _size => MediaQuery.sizeOf(this);

  double get screenWidth => _size.width;

  double get screenHeight => _size.height;

  /// True when the shortest side is tablet-class (iPad, tablets, folds).
  bool get isTablet =>
      math.min(_size.width, _size.height) >= kTabletBreakpoint;

  bool get isPhone => !isTablet;

  bool get isLandscape => _size.width > _size.height;

  /// Scale factor for HORIZONTAL dimensions (typography, horizontal spacing, radius).
  ///
  /// Based on width with reasonable clamping. Does NOT control vertical dimensions
  /// or component heights — those should use [heightScale] or constraint-based layout.
  double get textScale {
    final raw = _size.width / kDesignWidth;
    if (isTablet) return raw.clamp(1.0, 1.2);
    return raw.clamp(0.85, 1.15);
  }

  /// Scale factor for horizontal spacing/padding/radius (alias for textScale).
  double get spacingScale => textScale;

  /// Scale factor for VERTICAL dimensions (vertical spacing, heights).
  ///
  /// Based on height with reasonable clamping. Does NOT control horizontal dimensions
  /// or typography — those should use [textScale] or constraint-based layout.
  double get heightScale {
    final raw = _size.height / kDesignHeight;
    if (isTablet) return raw.clamp(1.0, 1.2);
    return raw.clamp(0.85, 1.15);
  }

  /// Scale factor for vertical spacing/padding/heights (alias for heightScale).
  double get verticalSpacingScale => heightScale;

  /// Scales a typography value from the Figma canvas.
  double rsFont(num designPx) => designPx * textScale;

  /// Scales a horizontal spacing/padding/radius value from the Figma canvas.
  double rs(num designPx) => designPx * spacingScale;

  /// Scales a vertical spacing/padding/height value from the Figma canvas.
  double rsV(num designPx) => designPx * verticalSpacingScale;

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
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pagePadding),
            child: child,
          ),
        ),
      );

  /// Returns a constrained width for full-width components on phone,
  /// or the max content width on tablet.
  double get constrainedContentWidth => isTablet ? contentMaxWidth : double.infinity;
}

/// A responsive screen wrapper that provides the correct constraint flow:
/// Viewport → SafeArea → centered/constrained content → child.
///
/// On phones: content uses full width, scrolls vertically if needed.
/// On tablets: content is centered with [contentMaxWidth] (default 560).
///
/// Uses ConstrainedBox(minHeight) to give Expanded/Spacer bounded constraints
/// without triggering intrinsic dimension conflicts.
class ResponsiveScreen extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveScreen({
    super.key,
    required this.child,
    this.backgroundColor,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = maxWidth ?? context.contentMaxWidth;
    final effectivePadding = padding ?? EdgeInsets.symmetric(horizontal: context.pagePadding);
    final viewportHeight = MediaQuery.of(context).size.height - MediaQuery.of(context).padding.vertical;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
                child: Padding(
                  padding: effectivePadding,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A responsive image that preserves its design aspect ratio while sizing
/// to its parent constraints. Replaces fixed `SizedBox(width: rs(...), height: rs(...))`.
///
/// Usage:
/// ```dart
/// ResponsiveImage(
///   assetPath: 'assets/images/hero.png',
///   designWidth: 369,
///   designHeight: 395,
///   borderRadius: 35,
///   fit: BoxFit.contain,
/// )
/// ```
class ResponsiveImage extends StatelessWidget {
  final String assetPath;
  final double designWidth;
  final double designHeight;
  final double? borderRadius;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final double? maxWidth;
  final double? maxHeight;

  const ResponsiveImage({
    super.key,
    required this.assetPath,
    required this.designWidth,
    required this.designHeight,
    this.borderRadius,
    this.fit = BoxFit.contain,
    this.errorBuilder,
    this.maxWidth,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Handle unbounded constraints — derive finite size from screen constraints
        final hasBoundedWidth = constraints.maxWidth.isFinite;
        final hasBoundedHeight = constraints.maxHeight.isFinite;

        final aspectRatio = designWidth / designHeight;

        double renderWidth;
        double renderHeight;

        if (hasBoundedWidth && hasBoundedHeight) {
          // Both bounded — fit within constraints preserving aspect ratio
          renderWidth = constraints.maxWidth;
          renderHeight = renderWidth / aspectRatio;

          if (renderHeight > constraints.maxHeight) {
            renderHeight = constraints.maxHeight;
            renderWidth = renderHeight * aspectRatio;
          }
        } else if (hasBoundedWidth) {
          // Only width bounded — use width, derive height from aspect ratio
          renderWidth = constraints.maxWidth;
          renderHeight = renderWidth / aspectRatio;
        } else if (hasBoundedHeight) {
          // Only height bounded — use height, derive width from aspect ratio
          renderHeight = constraints.maxHeight;
          renderWidth = renderHeight * aspectRatio;
        } else {
          // Neither bounded — derive from available screen space (minus padding)
          final availableWidth = context.screenWidth - context.pagePadding * 2;
          final availableHeight = context.screenHeight * 0.5; // max 50% of viewport height
          renderWidth = availableWidth;
          renderHeight = renderWidth / aspectRatio;

          if (renderHeight > availableHeight) {
            renderHeight = availableHeight;
            renderWidth = renderHeight * aspectRatio;
          }
        }

        // Apply optional max constraints
        if (maxWidth != null && renderWidth > maxWidth!) {
          renderWidth = maxWidth!;
          renderHeight = renderWidth / aspectRatio;
        }
        if (maxHeight != null && renderHeight > maxHeight!) {
          renderHeight = maxHeight!;
          renderWidth = renderHeight * aspectRatio;
        }

        Widget image = Image.asset(
          assetPath,
          width: renderWidth,
          height: renderHeight,
          fit: fit,
          errorBuilder: errorBuilder,
        );

        if (borderRadius != null && borderRadius! > 0) {
          image = ClipRRect(
            borderRadius: BorderRadius.circular(context.rs(borderRadius!)),
            child: image,
          );
        }

        return Center(child: image);
      },
    );
  }
}

/// A responsive card that constrains its width on tablet while using
/// full width on phone. Useful for form cards, button groups, etc.
class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? borderRadius;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.contentMaxWidth,
        ),
        child: child,
      ),
    );
  }
}

/// A responsive button that uses the design system dimensions but
/// constrains to available width on tablet.
class ResponsiveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? backgroundColor;
  final double? borderRadius;
  final double? minWidth;
  final double? maxWidth;
  final double height;

  const ResponsiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor,
    this.borderRadius,
    this.minWidth,
    this.maxWidth,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth ?? 0,
          maxWidth: maxWidth ?? context.contentMaxWidth,
        ),
        child: SizedBox(
          height: context.rsV(height),
          child: Material(
            color: backgroundColor ?? Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(borderRadius ?? context.rs(9999)),
            child: InkWell(
              borderRadius: BorderRadius.circular(borderRadius ?? context.rs(9999)),
              onTap: onPressed,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A responsive input field that constrains to content width on tablet.
class ResponsiveInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final double? maxWidth;

  const ResponsiveInput({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.contentMaxWidth,
        ),
        child: SizedBox(
          height: context.rsV(56),
          child: TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            obscureText: obscureText,
            onChanged: onChanged,
            style: AppTypography.bodyRegular(context, color: AppColors.darkText),
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              contentPadding: EdgeInsets.symmetric(
                horizontal: context.rs(16),
                vertical: context.rsV(16),
              ),
              labelStyle: AppTypography.bodyRegular(
                context,
                color: AppColors.mediumGray,
              ),
              hintStyle: AppTypography.bodyRegular(
                context,
                color: const Color(0xFF9CA3AF),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rs(16)),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rs(16)),
                borderSide: BorderSide(color: AppColors.buttonSolid, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rs(16)),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(context.rs(16)),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ),
    );
  }
}