import 'package:flutter/material.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Single source of truth for the `Tarek el araby` brand signature.
///
/// Figma: `Gardenia Summer`, weight 400, centered, single line. The
/// reference size is 128 design-px on the 393-wide reference frame, used
/// identically on Splash and the User Type Selection footer so the Hero
/// flight interpolates position only (no rescale).
///
/// Sizing goes through [AppTypography.signature] (the project's responsive
/// typography token, scaled from the 393 reference width). The full-width
/// box plus [FittedBox.scaleDown] is overflow safety only: measured
/// intrinsic width at 128px is ~255 logical px, so at the 393 reference
/// (and every supported phone/tablet width) no downscaling occurs.
class BrandSignatureLogo extends StatelessWidget {
  /// Figma design-px size (128 on both Splash and User Type Selection:
  /// the Hero flight moves position only and must not rescale the logo).
  final double designPx;

  /// Explicit signature colour (e.g. the Welcome screen's brand red).
  ///
  /// When null, Light Mode keeps the approved `Colors.black` (unchanged) and
  /// Dark Mode uses the semantic `textPrimary` (`#F2F4F7`), per ADR-009 D9.
  final Color? color;

  const BrandSignatureLogo({
    super.key,
    this.designPx = 128,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final effectiveColor =
        color ?? (semantic.isDark ? semantic.textPrimary : Colors.black);
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'Tarek el araby',
          maxLines: 1,
          textAlign: TextAlign.center,
          style: AppTypography.signature(
            context,
            designPx: designPx,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }
}
