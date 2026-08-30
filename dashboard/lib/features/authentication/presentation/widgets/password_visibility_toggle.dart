import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Password visibility toggle (Eye / Eye-off, 24 x 24 px) per the Figma
/// password field spec. Purely presentation state lives in the parent.
class PasswordVisibilityToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;

  const PasswordVisibilityToggle({
    super.key,
    required this.visible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onToggle,
      icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
      iconSize: 24,
      color: AppColors.iconInk,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      tooltip: visible ? 'Hide password' : 'Show password',
    );
  }
}
