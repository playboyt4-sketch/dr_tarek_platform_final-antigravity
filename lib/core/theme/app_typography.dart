import 'package:flutter/material.dart';
import '../responsive/responsive.dart';
import 'app_colors.dart';
import 'app_semantic_colors.dart';

abstract final class AppFontFamilies {
  static const googleSansFlex = 'Google Sans Flex';
  static const signature = 'Gardenia Summer';
}

abstract final class AppTypography {
  // Generic ThemeData fallback only (unscaled — no BuildContext available
  // at ThemeData construction time). Do NOT use these directly in screens.
  static const titleLargeFallback = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w400,
  );
  static const bodyRegularFallback = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // ---- Responsive styles — USE THESE IN EVERY SCREEN ----
  // Every fontSize below MUST go through context.rsFont(). This is the
  // one and only place font scaling happens; do not bypass it with
  // .copyWith(fontSize: ...) in screen code ever again.

  static TextStyle titleLarge(
    BuildContext context, {
    Color? color,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(28),
    fontWeight: FontWeight.w400,
    height: 36 / 28,
    color: color ?? AppSemanticColors.of(context).textPrimary,
  );

  static TextStyle titleMedium(
    BuildContext context, {
    Color? color,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(20),
    fontWeight: FontWeight.w400,
    height: 26 / 20,
    color: color ?? AppSemanticColors.of(context).textPrimary,
  );

  static TextStyle bodyRegular(
    BuildContext context, {
    Color? color,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(14),
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: color ?? AppSemanticColors.of(context).textPrimary,
  );

  static TextStyle bodyThin(
    BuildContext context, {
    Color? color,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(14),
    fontWeight: FontWeight.w100,
    fontVariations: const [FontVariation('wght', 100)],
    height: 20 / 14,
    color: color ?? AppSemanticColors.of(context).textSecondary,
  );

  static TextStyle captionSmall(
    BuildContext context, {
    Color? color,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(12),
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    color: color ?? AppSemanticColors.of(context).textSecondary,
  );

  static TextStyle signature(
    BuildContext context, {
    double designPx = 128,
    Color color = AppColors.black,
  }) => TextStyle(
    fontFamily: AppFontFamilies.signature,
    fontSize: context.rsFont(designPx),
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.0,
    // The signature is never underlined. Without this, a Hero flight
    // re-parents the logo Text into the Overlay, where it merges with
    // MaterialApp's fallback `DefaultTextStyle` (yellow double underline,
    // `_errorTextStyle` in app.dart) and paints a yellow bar under the
    // logo while it flies.
    decoration: TextDecoration.none,
  );

  /// EXPERIMENTAL brand-signature style (design experiment — NOT an
  /// approved design-system token, do NOT copy into `design system.md`
  /// without project-owner approval).
  ///
  /// Sizes the signature from the *available parent width* (already minus
  /// gutters) via [BrandSignatureResponsive], NOT from the viewport and
  /// NOT from the generic form/list [contentMaxWidth]. Pair with a
  /// single-line, overflow-safe wrapper (e.g. `FittedBox.scaleDown` purely
  /// as final overflow safety).
  static TextStyle brandSignatureFromAvailableWidth(
    double availableWidth, {
    Color color = AppColors.black,
  }) => TextStyle(
    fontFamily: AppFontFamilies.signature,
    fontSize: BrandSignatureResponsive.resolveFontSize(availableWidth),
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.0,
  );
}

/// EXPERIMENTAL responsive sizing for the brand signature (design
/// experiment — NOT an approved design-system token).
///
/// Maps the available parent content width to a signature font size:
///
/// ```text
/// availableWidth → preferred size → clamp(128, preferred, 192)
/// ```
///
/// - Monotonic non-decreasing in [availableWidth]: more meaningful space
///   never yields a smaller font.
/// - Constraint-driven: takes the parent's available width, never the
///   viewport. Contains no `width / 393`, no `height / 852`, and no
///   phone/tablet/web branches.
/// - Bounded: never below the pre-existing 128 design-px baseline, never
///   above the experimental 192 maximum, so large screens cannot grow the
///   signature indefinitely.
abstract final class BrandSignatureResponsive {
  /// EXPERIMENTAL minimum — the pre-existing 128 design-px baseline.
  static const minFontSize = 128.0;

  /// EXPERIMENTAL maximum for large tablets/web.
  static const maxFontSize = 192.0;

  /// Reference content width (393 design canvas minus 2x24 design gutter =
  /// 345) per baseline font px. A fixed design-derived constant, NOT a
  /// runtime viewport ratio: at the reference width the preferred size
  /// resolves back to ~baseline (345 / 2.695 = 128).
  static const _contentWidthPerFontPx = 345.0 / 128.0;

  /// Resolves the signature font size for [availableWidth] logical px.
  static double resolveFontSize(double availableWidth) =>
      (availableWidth / _contentWidthPerFontPx).clamp(
        minFontSize,
        maxFontSize,
      );
}
