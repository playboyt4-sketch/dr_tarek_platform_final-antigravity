import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';

/// Platform brand title from the Figma frame (452:397):
/// `Tarek el araby Platform` — Google Sans Flex Medium (500), 128 px,
/// black, rendered as a single run per the live frame.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final fontSize = context.rs(128);
    return Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'Tarek el araby Platform',
          style: AppTypography.brandTitleBase(fontSize: fontSize),
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ),
    );
  }
}
