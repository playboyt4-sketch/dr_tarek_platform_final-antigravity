import 'package:flutter/material.dart';

abstract final class AppFontFamilies {
  static const googleSansFlex = 'Google Sans Flex';
  static const signature = 'Gardenia Summer';
}

abstract final class AppTypography {
  static const titleLarge = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w400,
  );

  static const titleMedium = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w400,
  );

  static const bodyRegular = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const bodyThin = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w100,
  );

  static const captionSmall = TextStyle(
    fontFamily: AppFontFamilies.googleSansFlex,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  // --- LEGACY TOKENS PRESERVED FOR EXISTING SCREENS ---
  static const labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static TextStyle signature(
    BuildContext context, {
    required double designPx,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: AppFontFamilies.signature,
      fontSize: designPx,
      color: color,
    );
  }
}
