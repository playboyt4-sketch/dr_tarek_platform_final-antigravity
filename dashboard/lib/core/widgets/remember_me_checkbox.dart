import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_typography.dart';

/// "Remember me" control matching the approved Figma Dev Mode row
/// (128 x 24, right-aligned): SVG checkbox glyph (24 x 24) +
/// Light 300, 14 px, black label.
///
/// Toggles between `assets/images/check_box.svg` and
/// `assets/images/check_box_outline_blank.svg`.
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
            SvgPicture.asset(
              value
                  ? 'assets/images/check_box.svg'
                  : 'assets/images/check_box_outline_blank.svg',
              width: 24,
              height: 24,
              semanticsLabel:
                  value ? 'Remember me checked' : 'Remember me unchecked',
            ),
            const SizedBox(width: 8),
            Text('Remember me', style: AppTypography.rememberMeLogin()),
          ],
        ),
      ),
    );
  }
}
