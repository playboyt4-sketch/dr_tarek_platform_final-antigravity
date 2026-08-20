import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { filled, outlined, text }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    final button = switch (variant) {
      AppButtonVariant.filled => FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: child,
        style: _filledStyle,
      ),
      AppButtonVariant.outlined => OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: child,
        style: _outlinedStyle,
      ),
      AppButtonVariant.text => TextButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon),
        label: child,
      ),
    };

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  static final _filledStyle = FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    textStyle: AppTypography.labelLarge,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  static final _outlinedStyle = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    minimumSize: const Size.fromHeight(52),
    textStyle: AppTypography.labelLarge,
    side: const BorderSide(color: AppColors.primary),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
