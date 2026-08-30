import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// "Remember me" control matching the Figma checkbox group (452:397),
/// verified against the live frame: Material `check_box` /
/// `check_box_outline_blank` glyphs at 33 px in #1D1B20, followed by a
/// 12 px gap and the Light 24 px label.
class RememberMeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const RememberMeCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Remember me',
      checked: value,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 33,
              color: AppColors.checkboxInk,
            ),
            const SizedBox(width: 12),
            Text('Remember me', style: AppTypography.rememberMe()),
          ],
        ),
      ),
    );
  }
}
