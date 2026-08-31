import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light {
    return _buildTheme(
      canvasColor: AppColors.canvas,
      textColor: AppColors.textPrimary,
      surfaceColor: AppColors.itemSurface,
    );
  }

  // --- LEGACY THEME PRESERVED FOR EXISTING SCREENS ---
  static ThemeData get dark {
    return _buildTheme(
      canvasColor: AppColors.darkBackground,
      textColor: AppColors.darkOnBackground,
      surfaceColor: AppColors.darkSurface,
    );
  }

  static ThemeData get grade1 {
    return _buildTheme(
      canvasColor: AppColors.grade1Canvas,
      textColor: AppColors.grade1TextPrimary,
      surfaceColor: AppColors.grade1ItemSurface,
    );
  }

  static ThemeData get grade2 {
    return _buildTheme(
      canvasColor: AppColors.grade2Canvas,
      textColor: AppColors.grade2TextPrimary,
      surfaceColor: AppColors.grade2ItemSurface,
    );
  }

  static ThemeData get grade3 {
    return _buildTheme(
      canvasColor: AppColors.grade3Canvas,
      textColor: AppColors.grade3TextPrimary,
      surfaceColor: AppColors.grade3ItemSurface,
    );
  }

  static ThemeData get grade4 {
    return _buildTheme(
      canvasColor: AppColors.grade4Canvas,
      textColor: AppColors.grade4TextPrimary,
      surfaceColor: AppColors.grade4ItemSurface,
    );
  }

  static ThemeData _buildTheme({
    required Color canvasColor,
    required Color textColor,
    required Color surfaceColor,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.buttonSolid,
      brightness: Brightness.light,
      surface: canvasColor,
      onSurface: textColor,
    );

    final textTheme = TextTheme(
      displayLarge: AppTypography.titleLarge.copyWith(color: textColor),
      titleLarge: AppTypography.titleLarge.copyWith(color: textColor),
      titleMedium: AppTypography.titleMedium.copyWith(color: textColor),
      bodyLarge: AppTypography.bodyRegular.copyWith(color: textColor),
      bodyMedium: AppTypography.bodyThin.copyWith(color: textColor),
      bodySmall: AppTypography.captionSmall.copyWith(color: textColor),
      labelSmall: AppTypography.captionSmall.copyWith(color: textColor),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvasColor,
      fontFamily: AppFontFamilies.googleSansFlex,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSolid,
          foregroundColor: AppColors.canvas,
          minimumSize: const Size(AppComponentDimens.buttonWidth, AppComponentDimens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          ),
          textStyle: AppTypography.titleMedium,
        ),
      ),
    );
  }
}
