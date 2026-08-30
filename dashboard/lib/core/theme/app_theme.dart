import 'package:flutter/material.dart';

import 'app_typography.dart';

/// Material 3 theme for the Dashboard/Web app. Figma values win over
/// Material defaults wherever the dashboard login design specifies them.
abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.ink,
          surface: AppColors.background,
        ),
        fontFamily: AppTypography.fontFamily,
      );
}
