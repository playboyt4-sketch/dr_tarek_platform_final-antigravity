import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFFFFFFFF);
  static const black = Color(0xFF111827);
  static const darkText = Color(0xFF111827);
  static const mediumGray = Color(0xFF6B7280);
  static const itemSurface = Color(0xFFF3F4F6);
  static const buttonSolid = Color(0xFF1D4ED8);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  // Grade 1 (Yellow)
  static const grade1Canvas = Color(0xFFF59E0B);
  static const grade1TextPrimary = Color(0xFF111827);
  static const grade1ItemSurface = Color(0x1E000000); // 12% opacity black

  // Grade 2 (Blue)
  static const grade2Canvas = Color(0xFF1D4ED8);
  static const grade2TextPrimary = Color(0xFFFFFFFF);
  static const grade2ItemSurface = Color(0x26FFFFFF); // 15% opacity white

  // Grade 3 (Green)
  static const grade3Canvas = Color(0xFF15803D);
  static const grade3TextPrimary = Color(0xFFFFFFFF);
  static const grade3ItemSurface = Color(0x26FFFFFF); // 15% opacity white

  // Grade 4 (Red)
  static const grade4Canvas = Color(0xFFDC2626);
  static const grade4TextPrimary = Color(0xFFFFFFFF);
  static const grade4ItemSurface = Color(0x26FFFFFF); // 15% opacity white
  
  // Glass tokens
  static const buttonGlassBg = Color(0x33FFFFFF); // 20% opacity white
  static const buttonGlassBorder = Color(0x4DFFFFFF); // 30% opacity white
  
  static const cardGlassBg = Color(0x26FFFFFF); // 15% opacity white
  static const cardGlassBorder = Color(0x40FFFFFF); // 25% opacity white

  // --- LEGACY TOKENS PRESERVED FOR EXISTING SCREENS ---
  static const primary = Color(0xFF1A73E8);
  static const primaryLight = Color(0xFF4A9EFF);
  static const primaryDark = Color(0xFF0049B0);
  static const secondary = Color(0xFF00C853);
  static const secondaryLight = Color(0xFF5EFF84);
  static const secondaryDark = Color(0xFF009624);
  static const success = Color(0xFF4CAF50);
  static const warning = Color(0xFFFF9800);
  static const error = Color(0xFFE53935);
  static const info = Color(0xFF2196F3);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF5F7FB);
  static const onBackground = Color(0xFF212121);
  static const onSurface = Color(0xFF424242);
  static const divider = Color(0xFFE0E4EA);
  static const muted = Color(0xFF6B7280);
  static const gradeOne = Color(0xFFFBBC05);
  static const gradeTwo = Color(0xFF4285F4);
  static const gradeThree = Color(0xFF34A853);
  static const gradeFour = Color(0xFFEA4335);
  static const darkBackground = Color(0xFF121212);
  static const darkSurface = Color(0xFF1E1E1E);
  static const darkOnBackground = Color(0xFFFFFFFF);
  // Avatar legacy tokens
  static const avatarTeacherRing = Color(0xFFFFC96B);
  static const avatarAdminRing = Color(0xFFC084FC);
  static const avatarExternalRing = Color(0x80707070);
  static const avatarInternalRing = Color(0xFF5CF2D6);
  static const avatarGlass = Color(0x33FFFFFF);
  static const avatarBadgeDrStart = Color(0xFFFFC96B);
  static const avatarBadgeDrEnd = Color(0xFFD99A2B);
  static const avatarBadgeAdminStart = Color(0xFFC084FC);
  static const avatarBadgeAdminEnd = Color(0xFF7C3AED);
  static const avatarBadgeFreeStart = Color(0xFF60A5FA);
  static const avatarBadgeFreeEnd = Color(0xFF2563EB);
  static const avatarBadgeProStart = Color(0xFF5CF2D6);
  static const avatarBadgeProEnd = Color(0xFF10B981);
  static const avatarBadgeMaxStart = Color(0xFFF472B6);
  static const avatarBadgeMaxEnd = Color(0xFF9D174D);
}

abstract final class AppSpacing {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s36 = 36.0;

  // --- LEGACY TOKENS PRESERVED FOR EXISTING SCREENS ---
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const screenPadding = md;
  static const cardPadding = md;
  static const sectionGap = lg;
}

abstract final class AppShapes {
  static const radiusSm = 8.0;
  static const radiusMd = 16.0;
  static const radiusFull = 9999.0;

  // --- LEGACY TOKENS PRESERVED FOR EXISTING SCREENS ---
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusXLarge = 24.0;
  static const radiusCircular = 999.0;
  static const avatarDiameter = 56.0;
  static const avatarRingWidth = 2.0;
  static const avatarBadgeBottomOffset = -9.0;
  static const avatarBadgeHorizontalPadding = 7.0;
  static const avatarBadgeVerticalPadding = 2.0;
}

abstract final class AppComponentDimens {
  static const buttonWidth = 345.0;
  static const buttonHeight = 56.0;
  static const cardWidth = 345.0;
  static const cardHeight = 60.0;
  static const cardPaddingHorizontal = 20.0;
  static const cardPaddingVertical = 16.0;
}
