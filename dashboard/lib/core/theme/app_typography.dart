import 'package:flutter/material.dart';

/// Design tokens measured from the Figma file `education - os ui`
/// (dashboard login frame, Page 2) plus the platform-wide tokens already
/// approved for the mobile flow.
abstract final class AppColors {
  /// Platform light background from the Figma dashboard frames (#FFFFFF).
  static const Color background = Color(0xFFFFFFFF);

  /// Primary text/ink color from the dashboard login frame (#000000).
  static const Color ink = Color(0xFF000000);

  /// Icon stroke color from the Figma vector icons (#1E1E1E).
  static const Color iconInk = Color(0xFF1E1E1E);

  /// Material checkbox glyph color from the Figma checkbox instance
  /// (#1D1B20).
  static const Color checkboxInk = Color(0xFF1D1B20);

  /// Password field stroke: #000000 at 20% opacity.
  static const Color inputStroke = Color(0x33000000);

  /// Login button fill (#000000).
  static const Color buttonFill = Color(0xFF000000);
}

/// Google Sans Flex variable font (bundled asset). Weight axis spans
/// 1..1000; use [fontVariations] so the exact Figma weights render.
abstract final class AppTypography {
  static const String fontFamily = 'Google Sans Flex';

  /// Brand title — "Tarek el araby Platform" (128 px, black), a single
  /// Medium (500) run per the live Figma frame.
  static TextStyle brandTitleBase({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// "Login" card heading — SemiBold 36 px black.
  static TextStyle loginHeading({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 36,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// "Welcome back please login your account" — ExtraLight 24 px black.
  static TextStyle loginSubtitle({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w200,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 200),
        ],
      );

  /// Field placeholders — Thin 24 px black.
  static TextStyle fieldPlaceholder({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Input value text — Regular 24 px black for legible typed content.
  static TextStyle fieldValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// "Remember me" — Light 24 px black.
  static TextStyle rememberMe({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Login button label — Medium (500) white, verified from the live frame.
  static TextStyle buttonLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// Footer "Created by Tarek el araby" — Light (300) 16 px black, a
  /// single run per the live Figma frame.
  static TextStyle footerBase({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Dashboard home brand title — heavy run ("Tarek el araby", ~96 px).
  static TextStyle homeTitleHeavy({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// Dashboard home brand title — light run ("Platform").
  static TextStyle homeTitleLight({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Sidebar navigation item — Regular ~34 px black.
  static TextStyle sidebarItem({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.15,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Sidebar sub item (expanded grade) — Light ~30 px black.
  static TextStyle sidebarSubItem({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.15,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Content section heading ("Analytics & Reports") — Regular ~32 px.
  static TextStyle sectionHeading({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Stat card value — Medium ~44 px black.
  static TextStyle statValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// Stat card label / placeholder text — Light ~20 px black.
  static TextStyle statLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );
}
