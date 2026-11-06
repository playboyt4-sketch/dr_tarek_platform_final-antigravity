import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_semantic_colors.dart';
import 'app_typography.dart';

/// Approved application themes.
///
/// `light` is the canonical design and must not change visually.
/// `dark` is the additive second rendering approved by ADR-009; its values
/// come from `docs/notion/03_UI_UX.md` §2.2 and were verified against WCAG
/// 2.1 relative-luminance contrast before approval.
abstract final class AppTheme {
  static ThemeData get light => _buildLight();
  static ThemeData get dark => _buildDark();

  // ---------------------------------------------------------------------
  // Light — behaviour-preserving. Every value below matches the previously
  // shipped theme exactly; the only addition is the semantic extension,
  // which does not affect layout or painting on its own.
  // ---------------------------------------------------------------------
  static ThemeData _buildLight() {
    const semantic = AppSemanticColors.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.buttonSolid,
      brightness: Brightness.light,
      surface: semantic.canvas,
      onSurface: semantic.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: semantic.canvas,
      fontFamily: AppFontFamilies.googleSansFlex,
      textTheme: _textTheme(semantic.textPrimary),
      extensions: const <ThemeExtension<dynamic>>[AppSemanticColors.light],
      cardTheme: CardThemeData(
        color: semantic.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppShapes.radiusMd)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Light theme: white fields, independent of the screen surface
        // colour (product requirement; the Figma flows draw inputs as
        // white/transparent over the cream canvas).
        fillColor: AppColors.canvas,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s16,
        ),
        // Design-system input shape: radius/md with the documented
        // #D0D0D0 border. Making the fill white without a border would
        // make theme-styled fields (e.g. AppInput dialogs) disappear on
        // white surfaces, so the outline is part of the global default.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(
            color: AppColors.buttonSolid,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSolid,
          foregroundColor: AppColors.canvas,
          minimumSize: const Size(
            AppComponentDimens.buttonWidth,
            AppComponentDimens.buttonHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          ),
          textStyle: AppTypography.titleLargeFallback.copyWith(
            fontSize: 20,
            height: 26 / 20,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dark — approved tokens (03 UI & UX §2.2).
  //
  // The previous implementation built a *light* ColorScheme and only swapped
  // surface colours, which produced unreadable inputs. The brightness below
  // is correct, and every role is mapped explicitly.
  // ---------------------------------------------------------------------
  static ThemeData _buildDark() {
    const semantic = AppSemanticColors.dark;

    final base = ColorScheme.fromSeed(
      seedColor: AppColors.buttonSolid,
      brightness: Brightness.dark,
      surface: semantic.canvas,
      onSurface: semantic.textPrimary,
    );

    final colorScheme = base.copyWith(
      primary: semantic.primary,
      onPrimary: semantic.onPrimary,
      primaryContainer: semantic.primaryContainer,
      onPrimaryContainer: semantic.onPrimaryContainer,
      secondary: semantic.primary,
      onSecondary: semantic.onPrimary,
      secondaryContainer: semantic.primaryContainer,
      onSecondaryContainer: semantic.onPrimaryContainer,
      error: semantic.error,
      onError: semantic.onError,
      errorContainer: semantic.error,
      onErrorContainer: semantic.onError,
      surface: semantic.canvas,
      onSurface: semantic.textPrimary,
      onSurfaceVariant: semantic.textSecondary,
      surfaceDim: semantic.canvas,
      surfaceBright: semantic.surfaceContainerHigh,
      surfaceContainerLowest: semantic.surfaceContainerLow,
      surfaceContainerLow: semantic.surfaceContainerLow,
      surfaceContainer: semantic.surfaceContainer,
      surfaceContainerHigh: semantic.surfaceContainerHigh,
      surfaceContainerHighest: semantic.surfaceContainerHighest,
      outline: semantic.outline,
      outlineVariant: semantic.divider,
      inverseSurface: semantic.inverseSurface,
      onInverseSurface: semantic.onInverseSurface,
      scrim: semantic.scrim,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: semantic.canvas,
      canvasColor: semantic.canvas,
      cardColor: semantic.surface,
      dividerColor: semantic.divider,
      disabledColor: semantic.textDisabled,
      hintColor: semantic.inputHint,
      fontFamily: AppFontFamilies.googleSansFlex,
      textTheme: _textTheme(semantic.textPrimary),
      extensions: const <ThemeExtension<dynamic>>[AppSemanticColors.dark],
      iconTheme: IconThemeData(color: semantic.iconDefault),
      appBarTheme: AppBarTheme(
        backgroundColor: semantic.canvas,
        foregroundColor: semantic.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: semantic.iconDefault),
        titleTextStyle: AppTypography.titleLargeFallback.copyWith(
          color: semantic.textPrimary,
          fontSize: 20,
          height: 26 / 20,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: semantic.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(AppShapes.radiusMd),
          ),
          side: BorderSide(color: semantic.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantic.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s16,
        ),
        hintStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.inputHint,
        ),
        labelStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.textSecondary,
        ),
        floatingLabelStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.inputBorderFocused,
        ),
        errorStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.error,
        ),
        prefixIconColor: semantic.iconMuted,
        suffixIconColor: semantic.iconMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(color: semantic.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(color: semantic.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(
            color: semantic.inputBorderFocused,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(color: semantic.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(color: semantic.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide(color: semantic.divider),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: semantic.primary,
          foregroundColor: semantic.onPrimary,
          minimumSize: const Size(
            AppComponentDimens.buttonWidth,
            AppComponentDimens.buttonHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          ),
          textStyle: AppTypography.titleLargeFallback.copyWith(
            fontSize: 20,
            height: 26 / 20,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: semantic.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: semantic.primary,
          side: BorderSide(color: semantic.primary),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: semantic.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        barrierColor: semantic.scrim,
        titleTextStyle: AppTypography.titleLargeFallback.copyWith(
          color: semantic.textPrimary,
          fontSize: 20,
          height: 26 / 20,
        ),
        contentTextStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantic.surfaceContainer,
        modalBackgroundColor: semantic.surfaceContainer,
        modalBarrierColor: semantic.scrim,
        dragHandleColor: semantic.outline,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: semantic.snackbarBackground,
        contentTextStyle: AppTypography.bodyRegularFallback.copyWith(
          color: semantic.snackbarText,
        ),
        actionTextColor: semantic.primary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: semantic.navigationSurface,
        indicatorColor: semantic.navigationIndicator,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? semantic.primary
                : semantic.iconMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.bodyRegularFallback.copyWith(
            fontSize: 12,
            height: 16 / 12,
            color: states.contains(WidgetState.selected)
                ? semantic.primary
                : semantic.iconMuted,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: semantic.primary,
        unselectedLabelColor: semantic.textSecondary,
        indicatorColor: semantic.primary,
        dividerColor: semantic.divider,
      ),
      dividerTheme: DividerThemeData(color: semantic.divider),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: semantic.primary,
        selectionColor: semantic.selection,
        selectionHandleColor: semantic.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: semantic.primary,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: semantic.iconDefault,
        textColor: semantic.textPrimary,
      ),
    );
  }

  static TextTheme _textTheme(Color textColor) => TextTheme(
    displayLarge: AppTypography.titleLargeFallback.copyWith(color: textColor),
    titleLarge: AppTypography.titleLargeFallback.copyWith(color: textColor),
    titleMedium: AppTypography.titleLargeFallback.copyWith(
      color: textColor,
      fontSize: 20,
      height: 26 / 20,
    ),
    bodyLarge: AppTypography.bodyRegularFallback.copyWith(color: textColor),
    bodyMedium: AppTypography.bodyRegularFallback.copyWith(
      color: textColor,
      fontWeight: FontWeight.w100,
    ),
    bodySmall: AppTypography.bodyRegularFallback.copyWith(
      color: textColor,
      fontSize: 12,
      height: 16 / 12,
    ),
    labelSmall: AppTypography.bodyRegularFallback.copyWith(
      color: textColor,
      fontSize: 12,
      height: 16 / 12,
    ),
  );

  // --- LEGACY GRADED THEMES -------------------------------------------------
  // Preserved for backward compatibility. They have no call sites today, and
  // grade identity in Dark Mode is expressed with semantic accents (ADR-009
  // D3, Option B) rather than full-canvas themes.
  static ThemeData get grade1 => _buildLegacyGrade(
    canvasColor: AppColors.grade1Canvas,
    textColor: AppColors.grade1TextPrimary,
    surfaceColor: AppColors.grade1ItemSurface,
    brightness: Brightness.light,
  );

  static ThemeData get grade2 => _buildLegacyGrade(
    canvasColor: AppColors.grade2Canvas,
    textColor: AppColors.grade2TextPrimary,
    surfaceColor: AppColors.grade2ItemSurface,
    brightness: Brightness.dark,
  );

  static ThemeData get grade3 => _buildLegacyGrade(
    canvasColor: AppColors.grade3Canvas,
    textColor: AppColors.grade3TextPrimary,
    surfaceColor: AppColors.grade3ItemSurface,
    brightness: Brightness.dark,
  );

  static ThemeData get grade4 => _buildLegacyGrade(
    canvasColor: AppColors.grade4Canvas,
    textColor: AppColors.grade4TextPrimary,
    surfaceColor: AppColors.grade4ItemSurface,
    brightness: Brightness.dark,
  );

  static ThemeData _buildLegacyGrade({
    required Color canvasColor,
    required Color textColor,
    required Color surfaceColor,
    required Brightness brightness,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.buttonSolid,
      brightness: brightness,
      surface: canvasColor,
      onSurface: textColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvasColor,
      fontFamily: AppFontFamilies.googleSansFlex,
      textTheme: _textTheme(textColor),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        ),
      ),
    );
  }
}
