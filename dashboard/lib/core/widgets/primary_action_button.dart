import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Primary action button matching the approved Figma Dev Mode login CTA:
/// 345 x 56, full capsule (radius 9999), fill royal blue #1D4ED8 with a
/// 1 px white @ 30% border, label Google Sans Flex Regular 400 20 px white.
/// Loading state shows a centered 24 px white circular progress indicator.
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? semanticsLabel;

  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      label: semanticsLabel ?? label,
      button: true,
      enabled: enabled,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Reference geometry is 345 x 56; never exceed the available
          // width on compact viewports.
          final double width = constraints.maxWidth.isFinite
              ? constraints.maxWidth.clamp(0.0, 345)
              : 345;
          return SizedBox(
            width: width,
            height: 56,
            child: ElevatedButton(
              onPressed: enabled ? onPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonFill,
                disabledBackgroundColor:
                    AppColors.buttonFill.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(label, style: AppTypography.loginButtonLabel()),
            ),
          );
        },
      ),
    );
  }
}
