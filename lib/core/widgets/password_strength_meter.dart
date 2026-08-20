import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum PasswordStrength {
  none(0, '', Colors.transparent),
  weak(1, 'ضعيفة', AppColors.error),
  medium(2, 'متوسطة', AppColors.warning),
  strong(3, 'قوية', AppColors.success),
  veryStrong(4, 'قوية جداً', Color(0xFF00897B));

  final int level;
  final String label;
  final Color color;

  const PasswordStrength(this.level, this.label, this.color);

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
    final strength = PasswordStrength.evaluate(password);
    if (password.isEmpty) return const SizedBox.shrink();

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
                  backgroundColor: Colors.grey.shade300,
                  color: strength.color,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'قوة كلمة المرور: ${strength.label}',
              style: TextStyle(
                color: strength.color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (showRequirements) ...[
          const SizedBox(height: 8),
          _RequirementRow(label: '8 أحرف على الأقل', isMet: hasMinLength),
          _RequirementRow(label: 'حرف كبير (A-Z)', isMet: hasUppercase),
          _RequirementRow(label: 'حرف صغير (a-z)', isMet: hasLowercase),
          _RequirementRow(label: 'رقم (0-9)', isMet: hasDigit),
          _RequirementRow(label: 'رمز خاص (!@#\$%...)', isMet: hasSpecial),
        ],
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final bool isMet;

  const _RequirementRow({required this.label, required this.isMet});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isMet ? AppColors.success : AppColors.muted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isMet ? AppColors.success : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
