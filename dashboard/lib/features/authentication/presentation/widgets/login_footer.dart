import 'package:flutter/material.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_typography.dart';

/// Footer attribution from the Figma frame (452:397):
/// `Created by Tarek el araby` — Google Sans Flex Light (300), 16 px,
/// black, rendered as a single run per the live frame.
class LoginFooter extends StatelessWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final fontSize = context.rs(16, minScale: 0.8);
    return Text(
      'Created by Tarek el araby',
      style: AppTypography.footerBase(fontSize: fontSize),
      textAlign: TextAlign.center,
    );
  }
}
