import 'package:flutter/material.dart';

/// Semantic colour contract for the whole application.
///
/// Approved source of truth: `docs/notion/03_UI_UX.md` §2.1 (Light) and §2.2
/// (Dark), ratified by `20_ADR_009_Theme_Mode_Support.md`.
///
/// Presentation code must read roles from here (via
/// `Theme.of(context).extension<AppSemanticColors>()`) instead of hardcoding
/// `Color(0x...)` values, so a single theme switch re-renders every migrated
/// screen correctly.
///
/// Light values are a 1:1 mapping of the current approved constants — adding
/// this layer must not change any Light-mode pixel.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.canvas,
    required this.canvasWarm,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.iconDefault,
    required this.iconMuted,
    required this.divider,
    required this.outline,
    required this.inputFill,
    required this.inputBorder,
    required this.inputBorderSubtle,
    required this.inputBorderFocused,
    required this.inputHint,
    required this.inputFillDisabled,
    required this.primary,
    required this.primaryLegacy,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.error,
    required this.onError,
    required this.success,
    required this.warning,
    required this.info,
    required this.glassCardFill,
    required this.glassCardBorder,
    required this.glassButtonFill,
    required this.glassButtonBorder,
    required this.glassBackFill,
    required this.glassBackBorder,
    required this.glassText,
    required this.glassTextMuted,
    required this.scrim,
    required this.snackbarBackground,
    required this.snackbarText,
    required this.navigationSurface,
    required this.navigationIndicator,
    required this.selection,
    required this.gradeAccent1,
    required this.gradeAccent2,
    required this.gradeAccent3,
    required this.gradeAccent4,
    required this.gradeText1,
    required this.gradeText2,
    required this.gradeText3,
    required this.gradeText4,
    required this.isDark,
  });

  /// Scaffold / page background (`#FFFFFF` in Light, `#0B0D12` in Dark).
  final Color canvas;

  /// The Figma cream canvas (`#FFFCF7`) used by the onboarding screens.
  /// Kept as a separate role because Light Mode has two real canvases; in
  /// Dark Mode both resolve to the neutral dark canvas (ADR-009, Option B).
  final Color canvasWarm;

  /// Card / item surface.
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  final Color inverseSurface;
  final Color onInverseSurface;

  final Color textPrimary;
  final Color textSecondary;

  /// Pre-existing Light value `#9CA3AF` used by the password screen,
  /// promoted into the semantic layer so Light stays byte-identical.
  final Color textTertiary;

  final Color textDisabled;
  final Color iconDefault;
  final Color iconMuted;

  final Color divider;
  final Color outline;

  final Color inputFill;
  final Color inputBorder;

  /// The lighter per-screen border some Figma screens draw (`#E5E7EB` in
  /// Light). Preserved verbatim; resolves to the approved Dark input border.
  final Color inputBorderSubtle;

  final Color inputBorderFocused;
  final Color inputHint;
  final Color inputFillDisabled;

  /// Approved solid-action blue (`#1D4ED8` in Light).
  final Color primary;

  /// The second brand blue used by `AppButton` today (`#1A73E8` in Light).
  /// Owner decision D8: both blues are preserved in this mission; unifying
  /// them would change approved Light output.
  final Color primaryLegacy;

  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color error;
  final Color onError;
  final Color success;
  final Color warning;
  final Color info;

  /// `card/course-item` glass: Light 15%/25%, Dark 8%/14%.
  final Color glassCardFill;
  final Color glassCardBorder;

  /// `button/primary` glass: Light 20%/30%, Dark 12%/20%.
  final Color glassButtonFill;
  final Color glassButtonBorder;

  /// `button/back` glass: Light 25%/35%, Dark 14%/20%.
  final Color glassBackFill;
  final Color glassBackBorder;

  final Color glassText;
  final Color glassTextMuted;

  final Color scrim;
  final Color snackbarBackground;
  final Color snackbarText;
  final Color navigationSurface;
  final Color navigationIndicator;
  final Color selection;

  /// Grade identity accents (ADR-009 D3, Option B: neutral canvas + accent).
  final Color gradeAccent1;
  final Color gradeAccent2;
  final Color gradeAccent3;
  final Color gradeAccent4;

  /// Grade-specific readable text used on grade-tinted containers.
  final Color gradeText1;
  final Color gradeText2;
  final Color gradeText3;
  final Color gradeText4;

  final bool isDark;

  // ---------------------------------------------------------------------
  // Light — must equal the approved Light constants exactly.
  // ---------------------------------------------------------------------
  static const AppSemanticColors light = AppSemanticColors(
    canvas: Color(0xFFFFFFFF),
    canvasWarm: Color(0xFFFFFCF7),
    surface: Color(0xFFF3F4F6),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF3F4F6),
    surfaceContainerHigh: Color(0xFFF3F4F6),
    surfaceContainerHighest: Color(0xFFF5F7FB),
    inverseSurface: Color(0xFF111827),
    onInverseSurface: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textTertiary: Color(0xFF9CA3AF),
    textDisabled: Color(0xFF9A9A9A),
    iconDefault: Color(0xFF111827),
    iconMuted: Color(0xFF6B7280),
    divider: Color(0xFFE0E4EA),
    outline: Color(0xFFD0D0D0),
    inputFill: Color(0xFFFFFFFF),
    inputBorder: Color(0xFFD0D0D0),
    inputBorderSubtle: Color(0xFFE5E7EB),
    inputBorderFocused: Color(0xFF1D4ED8),
    inputHint: Color(0xFF9A9A9A),
    inputFillDisabled: Color(0xFFF3F4F6),
    primary: Color(0xFF1D4ED8),
    primaryLegacy: Color(0xFF1A73E8),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8EEFB),
    onPrimaryContainer: Color(0xFF1D4ED8),
    error: Color(0xFFE53935),
    onError: Color(0xFFFFFFFF),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFF9800),
    info: Color(0xFF2196F3),
    glassCardFill: Color(0x26FFFFFF),
    glassCardBorder: Color(0x40FFFFFF),
    glassButtonFill: Color(0x33FFFFFF),
    glassButtonBorder: Color(0x4DFFFFFF),
    glassBackFill: Color.fromRGBO(255, 255, 255, 0.25),
    glassBackBorder: Color.fromRGBO(255, 255, 255, 0.35),
    glassText: Color(0xFFFFFFFF),
    glassTextMuted: Color(0xFFF5F7FC),
    scrim: Color(0x8A000000),
    snackbarBackground: Color(0xFF111827),
    snackbarText: Color(0xFFFFFFFF),
    navigationSurface: Color(0xFFFFFFFF),
    navigationIndicator: Color(0xFFE8EEFB),
    selection: Color(0x331D4ED8),
    gradeAccent1: Color(0xFFF59E0B),
    gradeAccent2: Color(0xFF1D4ED8),
    gradeAccent3: Color(0xFF15803D),
    gradeAccent4: Color(0xFFDC2626),
    gradeText1: Color(0xFF111827),
    gradeText2: Color(0xFFFFFFFF),
    gradeText3: Color(0xFFFFFFFF),
    gradeText4: Color(0xFFFFFFFF),
    isDark: false,
  );

  // ---------------------------------------------------------------------
  // Dark — approved values (03 UI & UX §2.2). Every text/border pair was
  // measured against WCAG 2.1 before approval; see the ADR and the Phase 1
  // proposal for the contrast table.
  // ---------------------------------------------------------------------
  static const AppSemanticColors dark = AppSemanticColors(
    canvas: Color(0xFF0B0D12),
    canvasWarm: Color(0xFF0B0D12),
    surface: Color(0xFF15181F),
    surfaceElevated: Color(0xFF191D25),
    surfaceContainerLow: Color(0xFF12151B),
    surfaceContainer: Color(0xFF191D25),
    surfaceContainerHigh: Color(0xFF20242D),
    surfaceContainerHighest: Color(0xFF272C36),
    inverseSurface: Color(0xFFF2F4F7),
    onInverseSurface: Color(0xFF111827),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFFA7AEBC),
    textTertiary: Color(0xFF8E97A6),
    textDisabled: Color(0xFF6C7382),
    iconDefault: Color(0xFFD5DAE3),
    iconMuted: Color(0xFF8E97A6),
    divider: Color(0xFF2A2F3A),
    outline: Color(0xFF3A4150),
    inputFill: Color(0xFF15181F),
    inputBorder: Color(0xFF636C80),
    inputBorderSubtle: Color(0xFF636C80),
    inputBorderFocused: Color(0xFF7FA9FF),
    inputHint: Color(0xFF8E97A6),
    inputFillDisabled: Color(0xFF12151B),
    primary: Color(0xFF7FA9FF),
    primaryLegacy: Color(0xFF7FA9FF),
    onPrimary: Color(0xFF08142B),
    primaryContainer: Color(0xFF2B4E8F),
    onPrimaryContainer: Color(0xFFD8E3FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF5C0A0A),
    success: Color(0xFF7DD99A),
    warning: Color(0xFFFFC46B),
    info: Color(0xFF8CC8FF),
    glassCardFill: Color(0x14FFFFFF),
    glassCardBorder: Color(0x24FFFFFF),
    glassButtonFill: Color(0x1FFFFFFF),
    glassButtonBorder: Color(0x33FFFFFF),
    glassBackFill: Color(0x24FFFFFF),
    glassBackBorder: Color(0x33FFFFFF),
    glassText: Color(0xFFF2F4F7),
    glassTextMuted: Color(0xFFC6CCD8),
    scrim: Color(0x99000000),
    snackbarBackground: Color(0xFF272C36),
    snackbarText: Color(0xFFF2F4F7),
    navigationSurface: Color(0xFF12151B),
    navigationIndicator: Color(0xFF2B4E8F),
    selection: Color(0xFF1F3A6B),
    gradeAccent1: Color(0xFFF5B544),
    gradeAccent2: Color(0xFF7FA9FF),
    gradeAccent3: Color(0xFF6FD99A),
    gradeAccent4: Color(0xFFFF8A80),
    gradeText1: Color(0xFFFBEAD0),
    gradeText2: Color(0xFFF2F4F7),
    gradeText3: Color(0xFFEAF7EF),
    gradeText4: Color(0xFFFBEDEC),
    isDark: true,
  );

  /// Convenience lookup with a safe fallback so a widget rendered outside a
  /// themed subtree (tests, previews) never throws.
  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppSemanticColors copyWith({
    Color? canvas,
    Color? canvasWarm,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? iconDefault,
    Color? iconMuted,
    Color? divider,
    Color? outline,
    Color? inputFill,
    Color? inputBorder,
    Color? inputBorderSubtle,
    Color? inputBorderFocused,
    Color? inputHint,
    Color? inputFillDisabled,
    Color? primary,
    Color? primaryLegacy,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? error,
    Color? onError,
    Color? success,
    Color? warning,
    Color? info,
    Color? glassCardFill,
    Color? glassCardBorder,
    Color? glassButtonFill,
    Color? glassButtonBorder,
    Color? glassBackFill,
    Color? glassBackBorder,
    Color? glassText,
    Color? glassTextMuted,
    Color? scrim,
    Color? snackbarBackground,
    Color? snackbarText,
    Color? navigationSurface,
    Color? navigationIndicator,
    Color? selection,
    Color? gradeAccent1,
    Color? gradeAccent2,
    Color? gradeAccent3,
    Color? gradeAccent4,
    Color? gradeText1,
    Color? gradeText2,
    Color? gradeText3,
    Color? gradeText4,
    bool? isDark,
  }) {
    return AppSemanticColors(
      canvas: canvas ?? this.canvas,
      canvasWarm: canvasWarm ?? this.canvasWarm,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      iconDefault: iconDefault ?? this.iconDefault,
      iconMuted: iconMuted ?? this.iconMuted,
      divider: divider ?? this.divider,
      outline: outline ?? this.outline,
      inputFill: inputFill ?? this.inputFill,
      inputBorder: inputBorder ?? this.inputBorder,
      inputBorderSubtle: inputBorderSubtle ?? this.inputBorderSubtle,
      inputBorderFocused: inputBorderFocused ?? this.inputBorderFocused,
      inputHint: inputHint ?? this.inputHint,
      inputFillDisabled: inputFillDisabled ?? this.inputFillDisabled,
      primary: primary ?? this.primary,
      primaryLegacy: primaryLegacy ?? this.primaryLegacy,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      glassCardFill: glassCardFill ?? this.glassCardFill,
      glassCardBorder: glassCardBorder ?? this.glassCardBorder,
      glassButtonFill: glassButtonFill ?? this.glassButtonFill,
      glassButtonBorder: glassButtonBorder ?? this.glassButtonBorder,
      glassBackFill: glassBackFill ?? this.glassBackFill,
      glassBackBorder: glassBackBorder ?? this.glassBackBorder,
      glassText: glassText ?? this.glassText,
      glassTextMuted: glassTextMuted ?? this.glassTextMuted,
      scrim: scrim ?? this.scrim,
      snackbarBackground: snackbarBackground ?? this.snackbarBackground,
      snackbarText: snackbarText ?? this.snackbarText,
      navigationSurface: navigationSurface ?? this.navigationSurface,
      navigationIndicator: navigationIndicator ?? this.navigationIndicator,
      selection: selection ?? this.selection,
      gradeAccent1: gradeAccent1 ?? this.gradeAccent1,
      gradeAccent2: gradeAccent2 ?? this.gradeAccent2,
      gradeAccent3: gradeAccent3 ?? this.gradeAccent3,
      gradeAccent4: gradeAccent4 ?? this.gradeAccent4,
      gradeText1: gradeText1 ?? this.gradeText1,
      gradeText2: gradeText2 ?? this.gradeText2,
      gradeText3: gradeText3 ?? this.gradeText3,
      gradeText4: gradeText4 ?? this.gradeText4,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      canvas: mix(canvas, other.canvas),
      canvasWarm: mix(canvasWarm, other.canvasWarm),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceContainerLow: mix(surfaceContainerLow, other.surfaceContainerLow),
      surfaceContainer: mix(surfaceContainer, other.surfaceContainer),
      surfaceContainerHigh: mix(surfaceContainerHigh, other.surfaceContainerHigh),
      surfaceContainerHighest:
          mix(surfaceContainerHighest, other.surfaceContainerHighest),
      inverseSurface: mix(inverseSurface, other.inverseSurface),
      onInverseSurface: mix(onInverseSurface, other.onInverseSurface),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      iconDefault: mix(iconDefault, other.iconDefault),
      iconMuted: mix(iconMuted, other.iconMuted),
      divider: mix(divider, other.divider),
      outline: mix(outline, other.outline),
      inputFill: mix(inputFill, other.inputFill),
      inputBorder: mix(inputBorder, other.inputBorder),
      inputBorderSubtle: mix(inputBorderSubtle, other.inputBorderSubtle),
      inputBorderFocused: mix(inputBorderFocused, other.inputBorderFocused),
      inputHint: mix(inputHint, other.inputHint),
      inputFillDisabled: mix(inputFillDisabled, other.inputFillDisabled),
      primary: mix(primary, other.primary),
      primaryLegacy: mix(primaryLegacy, other.primaryLegacy),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryContainer: mix(primaryContainer, other.primaryContainer),
      onPrimaryContainer: mix(onPrimaryContainer, other.onPrimaryContainer),
      error: mix(error, other.error),
      onError: mix(onError, other.onError),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      info: mix(info, other.info),
      glassCardFill: mix(glassCardFill, other.glassCardFill),
      glassCardBorder: mix(glassCardBorder, other.glassCardBorder),
      glassButtonFill: mix(glassButtonFill, other.glassButtonFill),
      glassButtonBorder: mix(glassButtonBorder, other.glassButtonBorder),
      glassBackFill: mix(glassBackFill, other.glassBackFill),
      glassBackBorder: mix(glassBackBorder, other.glassBackBorder),
      glassText: mix(glassText, other.glassText),
      glassTextMuted: mix(glassTextMuted, other.glassTextMuted),
      scrim: mix(scrim, other.scrim),
      snackbarBackground: mix(snackbarBackground, other.snackbarBackground),
      snackbarText: mix(snackbarText, other.snackbarText),
      navigationSurface: mix(navigationSurface, other.navigationSurface),
      navigationIndicator: mix(navigationIndicator, other.navigationIndicator),
      selection: mix(selection, other.selection),
      gradeAccent1: mix(gradeAccent1, other.gradeAccent1),
      gradeAccent2: mix(gradeAccent2, other.gradeAccent2),
      gradeAccent3: mix(gradeAccent3, other.gradeAccent3),
      gradeAccent4: mix(gradeAccent4, other.gradeAccent4),
      gradeText1: mix(gradeText1, other.gradeText1),
      gradeText2: mix(gradeText2, other.gradeText2),
      gradeText3: mix(gradeText3, other.gradeText3),
      gradeText4: mix(gradeText4, other.gradeText4),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
