import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_semantic_colors.dart';
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
/// primary button going forward.
///
/// Colours come from [AppSemanticColors] (ADR-009):
/// - [ButtonVariant.solid]: Light `#1D4ED8` fill / white text;
///   Dark `#7FA9FF` fill / `#08142B` text.
/// - [ButtonVariant.glass]: Light White 20% fill + 30% border with white
///   text; Dark White 12% fill + 20% border with `#F2F4F7` text.
///   Blur radius (24px) and geometry are identical in both appearances.
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
    final semantic = AppSemanticColors.of(context);
    final textStyle = AppTypography.titleMedium(
      context,
      color: semantic.isDark ? semantic.glassText : semantic.onPrimary,
    );

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
                color: semantic.glassButtonFill,
                borderRadius: BorderRadius.circular(AppShapes.radiusFull),
                border: Border.all(color: semantic.glassButtonBorder),
              ),
              child: _Label(
                label: label,
                onPressed: onPressed,
                textStyle: AppTypography.titleMedium(
                  context,
                  color: semantic.glassText,
                ),
              ),
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
          backgroundColor: semantic.primary,
          foregroundColor: semantic.onPrimary,
          disabledBackgroundColor: semantic.primary.withValues(
            alpha: semantic.isDark ? 0.30 : 0.40,
          ),
          disabledForegroundColor: semantic.onPrimary.withValues(
            alpha: semantic.isDark ? 0.60 : 0.80,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.radiusFull),
          ),
        ),
        child: Text(label, style: textStyle),
      ),
    );
  }
}

/// Glass-variant label/tap surface (transparent material over the blur).
class _Label extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final TextStyle textStyle;

  const _Label({
    required this.label,
    required this.onPressed,
    required this.textStyle,
  });

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
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
