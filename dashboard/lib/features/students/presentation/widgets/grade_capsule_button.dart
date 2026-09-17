import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';

/// Shared grade capsule action button.
///
/// Figma spec: `height 36`, `radius 9999`, filled with the current grade
/// semantic [gradeColor]; white `14px Medium` label. Subject actions use
/// Edit `90px` / Add Lecture `130px` / Delete Subject `130px`; lecture
/// rows pass a compact `height`/`width` override. The grade color is
/// always injected, never hardcoded.
class GradeCapsuleButton extends StatelessWidget {
  final String label;
  final Color gradeColor;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double fontSize;
  final Color? textColor;

  const GradeCapsuleButton({
    super.key,
    required this.label,
    required this.gradeColor,
    this.onPressed,
    this.width,
    this.height = 36,
    this.fontSize = 14,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: gradeColor,
          foregroundColor: textColor ?? Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: textColor ?? Colors.white,
          ),
        ),
      ),
    );
  }
}
