import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Figma `❖ button/primary` variants.
enum ButtonVariant {
  /// Solid royal-blue button for white pre-login screens.
  solid,

  /// Glass button for grade-tinted post-login surfaces.
  glass,
}

/// Canonical primary call-to-action button (Figma `❖ button/primary`).
///
/// Geometry: full-width (capped at 345px by the parent), 56px tall,
/// `radius/full` (9999px). Label uses `title/medium` (20px Regular).
///
/// NOTE (no-duplication record): no `PrimaryButton` existed in the project
/// before this file — sibling auth screens used inline `ElevatedButton`
/// markup and `core/widgets/app_button.dart` (`AppButton`) uses different
/// geometry (52px tall, 12px radius). This widget is the single canonical
/// primary button going forward: fix the remaining inline copies to use it
/// in follow-up tasks instead of copying this markup again.
///
/// - [ButtonVariant.solid]: fill `#1D4ED8`, white text (design_system.md
///   "Style = Solid (فوق الشاشات البيضاء)").
/// - [ButtonVariant.glass]: fill White 20% + 1px White 30% stroke with a
///   24px backdrop blur (design_system.md "Style = Glass").
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.solid,
  });

  @override
  Widget build(BuildContext context) {
    if (variant == ButtonVariant.glass) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.buttonGlassBg,
                borderRadius: BorderRadius.circular(AppShapes.radiusFull),
                border: Border.all(color: AppColors.buttonGlassBorder),
              ),
              child: _Label(label: label, onPressed: onPressed),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSolid,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AppColors.buttonSolid.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.titleMedium(context, color: Colors.white),
        ),
      ),
    );
  }
}

/// Glass-variant label/tap surface (transparent material over the blur).
class _Label extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _Label({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.radiusFull),
        onTap: onPressed,
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium(context, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
