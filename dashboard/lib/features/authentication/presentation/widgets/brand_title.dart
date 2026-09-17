import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Platform brand title from the approved Figma Dev Mode spec
/// (`dashboard login`, 1280 x 800 baseline):
/// max width 1120, centered, Google Sans Flex 96 px —
/// "Tarek el araby" Regular (400) black + " " Medium (500) +
/// "Platform" Thin (100) #979797.
///
/// Implemented as a single [Text.rich] so the plain-text run
/// ("Tarek el araby Platform") stays discoverable for semantics/tests.
/// Font scales responsively, clamped between 48 px and 96 px, so the
/// header shrinks gracefully below 1280 px without overflowing.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    // 96 px at the 1280 baseline, clamped to [48, 96] per spec.
    final double fontSize =
        (96 * (screenWidth / 1280)).clamp(48.0, 96.0).toDouble();
    final double width =
        screenWidth < 1200 ? (screenWidth - 48).clamp(0.0, 1120.0) : 1120;
    return Semantics(
      header: true,
      child: SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: <TextSpan>[
                TextSpan(
                  text: 'Tarek el araby',
                  style: AppTypography.brandTitleHeavy(fontSize: fontSize),
                ),
                TextSpan(
                  text: ' ',
                  style: AppTypography.brandTitleSpace(fontSize: fontSize),
                ),
                TextSpan(
                  text: 'Platform',
                  style: AppTypography.brandTitlePlatform(fontSize: fontSize),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
