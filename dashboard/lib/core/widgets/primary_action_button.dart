import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Primary action button matching the Figma dashboard login button:
/// 424 x 50, corner radius 28, fill #000000, centered label.
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
          // Reference geometry is 424 x 50; never exceed the available
          // width on compact viewports.
          final double width = constraints.maxWidth.isFinite
              ? constraints.maxWidth.clamp(0.0, 424)
              : 424;
          return SizedBox(
            width: width,
            height: 50,
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
                  borderRadius: BorderRadius.circular(28),
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
                  : Text(label, style: AppTypography.buttonLabel()),
            ),
          );
        },
      ),
    );
  }
}
