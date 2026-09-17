import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Footer attribution from the approved Figma Dev Mode spec (bottom of
/// the card): `Created by Tarek el araby` — Google Sans Flex 16 px black
/// ("Created by" Thin 100, " " Light 300, "Tarek el araby" Regular 400).
///
/// Single [Text.rich] so the plain text stays one run for semantics/tests.
class LoginFooter extends StatelessWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(
            text: 'Created by',
            style: AppTypography.loginFooterCreatedBy(),
          ),
          TextSpan(
            text: ' ',
            style: AppTypography.loginFooterSpace(),
          ),
          TextSpan(
            text: 'Tarek el araby',
            style: AppTypography.loginFooterName(),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
    );
  }
}
