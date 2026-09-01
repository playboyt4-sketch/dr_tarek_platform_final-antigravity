import 'package:flutter/material.dart';
import '../responsive/responsive.dart';
import 'app_colors.dart';

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
    Color color = AppColors.darkText,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(28),
    fontWeight: FontWeight.w400,
    height: 36 / 28,
    color: color,
  );

  static TextStyle titleMedium(
    BuildContext context, {
    Color color = AppColors.darkText,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(20),
    fontWeight: FontWeight.w400,
    height: 26 / 20,
    color: color,
  );

  static TextStyle bodyRegular(
    BuildContext context, {
    Color color = AppColors.darkText,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(14),
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: color,
  );

  static TextStyle bodyThin(
    BuildContext context, {
    Color color = AppColors.mediumGray,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(14),
    fontWeight: FontWeight.w100,
    fontVariations: const [FontVariation('wght', 100)],
    height: 20 / 14,
    color: color,
  );

  static TextStyle captionSmall(
    BuildContext context, {
    Color color = AppColors.mediumGray,
  }) => TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: context.rsFont(12),
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    color: color,
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
  );
}
