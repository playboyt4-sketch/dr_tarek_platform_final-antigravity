import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Shared platform brand lockup — `Tarek el araby Platform`.
///
/// 540 x 80, centered: "Tarek el araby" Regular 400 black +
/// "Platform" Thin 100, 48 px, single line (FittedBox scaleDown).
/// Extracted from the grade screens so every 1280 x 800 page renders
/// the identical header without duplicating the layout.
class DashboardBrandLockup extends StatelessWidget {
  /// Ink override for the Thin "Platform" run. The grade screens render
  /// it in page ink (black); defaults to [AppColors.ink] to match.
  final Color lightColor;

  const DashboardBrandLockup({
    super.key,
    this.lightColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      height: 80,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text.rich(
          TextSpan(
            children: <TextSpan>[
              TextSpan(
                text: 'Tarek el araby ',
                style: AppTypography.homeBrandHeavy(fontSize: 48),
              ),
              TextSpan(
                text: 'Platform',
                style: AppTypography.homeBrandLight(fontSize: 48)
                    .copyWith(color: lightColor),
              ),
            ],
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}
