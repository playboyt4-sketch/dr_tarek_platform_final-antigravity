import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';

enum PasswordStrength {
  none(0, ''),
  weak(1, 'ضعيفة'),
  medium(2, 'متوسطة'),
  strong(3, 'قوية'),
  veryStrong(4, 'قوية جداً');

  final int level;
  final String label;

  const PasswordStrength(this.level, this.label);

  static PasswordStrength evaluate(String password) {
    if (password.isEmpty) return PasswordStrength.none;

    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=\[\]/\\`~]'))) {
      score++;
    }

    if (score <= 1) return PasswordStrength.weak;
    if (score <= 3) return PasswordStrength.medium;
    if (score == 4) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  /// Resolves the strength colour from the semantic layer.
  ///
  /// Light keeps the exact previous values (`#E53935` / `#FF9800` /
  /// `#4CAF50` / `#00897B`). Dark uses the approved status tokens; the
  /// pre-existing teal has no approved dark counterpart, so the approved
  /// success green is used for `veryStrong` instead of inventing a token.
  Color resolveColor(AppSemanticColors semantic) => switch (this) {
    PasswordStrength.none => Colors.transparent,
    PasswordStrength.weak => semantic.error,
    PasswordStrength.medium => semantic.warning,
    PasswordStrength.strong => semantic.success,
    PasswordStrength.veryStrong =>
      semantic.isDark ? semantic.success : const Color(0xFF00897B),
  };
}

class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  final bool showRequirements;

  const PasswordStrengthMeter({
    required this.password,
    this.showRequirements = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final strength = PasswordStrength.evaluate(password);
    if (password.isEmpty) return const SizedBox.shrink();

    final strengthColor = strength.resolveColor(semantic);
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=\[\]/\\`~]'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: strength.level / 4.0,
                  // Light keeps the pre-existing grey track verbatim; Dark
                  // uses the approved surface-container-high role.
                  backgroundColor: semantic.isDark
                      ? semantic.surfaceContainerHigh
                      : const Color(0xFFE0E0E0),
                  color: strengthColor,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'قوة كلمة المرور: ${strength.label}',
              style: TextStyle(
                color: strengthColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (showRequirements) ...[
          const SizedBox(height: 8),
          _RequirementRow(
            label: '8 أحرف على الأقل',
            isMet: hasMinLength,
            semantic: semantic,
          ),
          _RequirementRow(
            label: 'حرف كبير (A-Z)',
            isMet: hasUppercase,
            semantic: semantic,
          ),
          _RequirementRow(
            label: 'حرف صغير (a-z)',
            isMet: hasLowercase,
            semantic: semantic,
          ),
          _RequirementRow(
            label: 'رقم (0-9)',
            isMet: hasDigit,
            semantic: semantic,
          ),
          _RequirementRow(
            label: 'رمز خاص (!@#\$%...)',
            isMet: hasSpecial,
            semantic: semantic,
          ),
        ],
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final bool isMet;
  final AppSemanticColors semantic;

  const _RequirementRow({
    required this.label,
    required this.isMet,
    required this.semantic,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMet ? semantic.success : semantic.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}
