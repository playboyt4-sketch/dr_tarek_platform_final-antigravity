import 'package:flutter/material.dart';

/// Design tokens measured from the Figma frame `dashboard login`
/// (1280 x 800 reference): white page, liquid-glass card 480 x 452,
/// royal-blue capsule button, plus platform-wide tokens.
abstract final class AppColors {
  /// Page background — pure white (#FFFFFF).
  static const Color background = Color(0xFFFFFFFF);

  /// Primary text/ink color (legacy token, kept for compat).
  static const Color ink = Color(0xFF000000);

  /// Card heading ink (#111827) — "Login" 32 SemiBold.
  static const Color headingInk = Color(0xFF111827);

  /// Subtitle / secondary ink (#6B7280) — subtitle + field icons.
  static const Color subtitleInk = Color(0xFF6B7280);

  /// Hint / muted ink (#9CA3AF) — placeholders + branding + "Platform".
  static const Color hintInk = Color(0xFF9CA3AF);

  /// "Remember me" label ink (#374151).
  static const Color rememberInk = Color(0xFF374151);

  /// Icon color from the approved frame (#6B7280, 40 x 40 instances).
  static const Color iconInk = Color(0xFF6B7280);

  /// Material checkbox glyph color — aligned to "Remember me" ink.
  static const Color checkboxInk = Color(0xFF374151);

  /// Input + card stroke (#E5E7EB).
  static const Color inputStroke = Color(0xFFE5E7EB);

  /// Login input stroke from the Figma Dev Mode spec (#979797, 1 px).
  static const Color loginInputStroke = Color(0xFF979797);

  /// "Platform" brand run gray from the Figma Dev Mode spec (#979797).
  static const Color platformGray = Color(0xFF979797);

  /// Card stroke alias (1.5 px, inside).
  static const Color cardStroke = Color(0xFFE5E7EB);

  /// Liquid-glass card fill — White 70% (Color(0xB3FFFFFF)).
  static const Color cardFill = Color(0xB3FFFFFF);

  /// Card drop shadow color — black @ ~12% (0x1E000000, offset 0/12,
  /// blur 30) per the Figma Dev Mode spec.
  static const Color cardShadow = Color(0x1E000000);

  /// Login button fill — royal blue (#1D4ED8).
  static const Color buttonFill = Color(0xFF1D4ED8);

  /// Home analytics grade accents.
  static const Color gradeOne = Color(0xFFF59E0B);
  static const Color gradeTwo = Color(0xFF1D4ED8);
  static const Color gradeThree = Color(0xFF15803D);
  static const Color gradeFour = Color(0xFFDC2626);

  /// Student activity "Active Today" green (#10B981).
  static const Color activityGreen = Color(0xFF10B981);

  /// Bottom action cards fill (#F3F4F6) + stroke (#E2E8F0).
  static const Color actionCardFill = Color(0xFFF3F4F6);
  static const Color actionCardStroke = Color(0xFFE2E8F0);

  /// Chart curve ink (#111827, shared with [headingInk]).
  static const Color chartInk = Color(0xFF111827);

  /// Pill button fill (#111827).
  static const Color pillFill = Color(0xFF111827);

  /// Status badge fills + inks.
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color successInk = Color(0xFF059669);
  static const Color errorSoft = Color(0xFFFEF2F2);
  static const Color errorInk = Color(0xFFDC2626);

  /// Neutral capsule fill (#F3F4F6).
  static const Color neutralSoft = Color(0xFFF3F4F6);
}

/// Google Sans Flex variable font (bundled asset). Weight axis spans
/// 1..1000; use [fontVariations] so the exact Figma weights render.
abstract final class AppTypography {
  static const String fontFamily = 'Google Sans Flex';

  /// Brand title — "Tarek el araby Platform" (96 px). The live frame
  /// renders "Tarek el araby" Regular (400) black + "Platform" Thin
  /// (100) #9CA3AF as two runs; this base stays for compat.
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

  /// Brand heavy run — "Tarek el araby" Regular 400 black, 96 px.
  static TextStyle brandTitleHeavy({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 96,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Brand light run — "Platform" Thin 100 #9CA3AF, 96 px.
  static TextStyle brandTitleLight({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 96,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.hintInk,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Brand spacer run — " " Medium 500, 96 px (Figma Dev Mode spec).
  static TextStyle brandTitleSpace({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 96,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// Brand "Platform" run — Thin 100 #979797, 96 px
  /// (Figma Dev Mode spec for the dashboard login header).
  static TextStyle brandTitlePlatform({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 96,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.platformGray,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Login input hint — Thin 100, 24 px, black
  /// (Figma Dev Mode spec: "Phone Number" / "Password").
  static TextStyle loginFieldPlaceholder({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Login input value — Regular 400, 24 px, black (matches hint size so
  /// typed text aligns with the Figma placeholder geometry).
  static TextStyle loginFieldValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 24,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// "Remember me" login label — Light 300, 14 px, black
  /// (Figma Dev Mode spec).
  static TextStyle rememberMeLogin({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Login CTA label — Regular 400, 20 px, white (Figma Dev Mode spec).
  static TextStyle loginButtonLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 20,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.white,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Footer "Created by" run — Thin 100, 16 px, black.
  static TextStyle loginFooterCreatedBy({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Footer spacer run — Light 300, 16 px, black.
  static TextStyle loginFooterSpace({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Footer "Tarek el araby" run — Regular 400, 16 px, black.
  static TextStyle loginFooterName({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.black,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// "Login" card heading — SemiBold 32 px #111827.
  static TextStyle loginHeading({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 32,
        height: 1.5,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// "Welcome back please login your account" — Regular 16 px #6B7280.
  static TextStyle loginSubtitle({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.5,
        letterSpacing: 0,
        color: AppColors.subtitleInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Field placeholders — Regular 16 px #9CA3AF.
  static TextStyle fieldPlaceholder({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.hintInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Input value text — Regular 16 px #111827 for legible typed content.
  static TextStyle fieldValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// "Remember me" — Regular 14 px #374151.
  static TextStyle rememberMe({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.rememberInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Login button label — Medium (500) 16 px white.
  static TextStyle buttonLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// Footer "Created by Tarek el araby" — Regular (400) 14 px #9CA3AF.
  /// The "Tarek el araby" run renders Thin (100); see [footerThin].
  static TextStyle footerBase({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.hintInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Footer thin run — "Tarek el araby" Thin (100) 14 px #9CA3AF.
  static TextStyle footerThin({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.hintInk,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
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

  // ------------------------------------------------------------------
  // Dashboard home (1280 x 800) + full menu tokens.
  // ------------------------------------------------------------------

  /// Home header brand — heavy run 48 px Regular 400 black.
  static TextStyle homeBrandHeavy({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 48,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Home header brand — light run 48 px Thin 100.
  static TextStyle homeBrandLight({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 48,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w100,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 100),
        ],
      );

  /// Full-menu master item (T Home / T Grades / T Management) —
  /// 32 px Regular 400 black per DASHBOARD_FULL_MENU_SPEC.
  static TextStyle menuSection({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 32,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Full-menu master entry — 32 px Regular 400 black (Home).
  static TextStyle menuItem({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 32,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Full-menu sub item (Frame 30 / Frame 31) — 20 px Light 300 black,
  /// line height 1.2 (= 24 px row) per DASHBOARD_FULL_MENU_SPEC.
  static TextStyle menuSubItem({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 20,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.ink,
        fontWeight: FontWeight.w300,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 300),
        ],
      );

  /// Pie "Total Students" caption — 14 px #6B7280.
  static TextStyle totalCaption({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.subtitleInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Pie total value — 28 px bold #111827.
  static TextStyle totalValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 28,
        height: 1.1,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w700,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 700),
        ],
      );

  /// Grade card title — 20 px SemiBold #111827.
  static TextStyle gradeTitle({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 20,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// Grade card metric label — 12 px #6B7280.
  static TextStyle gradeLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 12,
        height: 1.3,
        letterSpacing: 0,
        color: AppColors.subtitleInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Grade card metric value — 16 px SemiBold #111827.
  static TextStyle gradeValue({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 16,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// Action card title — 20 px SemiBold #111827.
  static TextStyle actionTitle({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 20,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// Action card description — 12 px #6B7280.
  static TextStyle actionDesc({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 12,
        height: 1.4,
        letterSpacing: 0,
        color: AppColors.subtitleInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
        ],
      );

  /// Pill button label — 14 px Medium white.
  static TextStyle pillLabel({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 14,
        height: 1.0,
        letterSpacing: 0,
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 500),
        ],
      );

  /// Chart section title — 20 px SemiBold #111827.
  static TextStyle chartTitle({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 20,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.headingInk,
        fontWeight: FontWeight.w600,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 600),
        ],
      );

  /// Chart axis tick — 12 px #6B7280.
  static TextStyle chartTick({double? fontSize}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize ?? 12,
        height: 1.0,
        letterSpacing: 0,
        color: AppColors.subtitleInk,
        fontWeight: FontWeight.w400,
        fontVariations: const <FontVariation>[
          FontVariation('wght', 400),
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
