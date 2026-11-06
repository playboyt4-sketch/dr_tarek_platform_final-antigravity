import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 8 guardrail.
///
/// The 11 Figma-specified screens were migrated to `AppSemanticColors`. Their
/// remaining raw `Color(0x........)` literals are deliberate Light-only or
/// brand values; every one is frozen below so a future edit cannot silently
/// reintroduce a hardcoded theme colour. A legitimate change must update this
/// list (and therefore be reviewed).
const _screensDir =
    'lib/features/authentication/presentation/screens';
const _studentHome =
    'lib/features/student_home/presentation/screens/student_home_screen.dart';

const _allowedHexByFile = <String, Set<String>>{
  'splash_screen.dart': <String>{},
  'user_type_selection_screen.dart': <String>{
    // Brand card amber/red + cream title on the red card.
    'Color(0xFFF59E0B)',
    'Color(0xFFDC2626)',
    'Color(0xFF111827)',
    'Color(0xFFFFFCF7)',
  },
  'new_student_welcome_screen.dart': <String>{
    // Approved brand signature red.
    'Color(0xFFDC2626)',
  },
  'new_student_name_screen.dart': <String>{
    // Retained Light reference constant.
    'Color(0xFFFFFCF7)',
  },
  'new_student_number_screen.dart': <String>{
    // Retained Light reference constant.
    'Color(0xFFFFFCF7)',
  },
  'new_student_photo_screen.dart': <String>{
    // Retained Light reference constant + Light-only glass sheet/handle.
    'Color(0xFFFFFCF7)',
    'Color(0x4CFFFCF7)',
    'Color(0xFFE5E7EB)',
  },
  'new_student_grade_screen.dart': <String>{
    // Retained Light reference constant.
    'Color(0xFFFFFCF7)',
  },
  'new_student_password_screen.dart': <String>{
    // Retained Light reference constant (`primaryBlue`).
    'Color(0xFF1D4ED8)',
  },
  'new_student_end_screen.dart': <String>{
    // Retained Light reference constants.
    'Color(0xFFFFFCF7)',
    'Color(0xFF1D4ED8)',
  },
  'login_screen.dart': <String>{},
  _studentHome: <String>{
    // Light-only grade/carousel/bottom-pill material.
    'Color(0x4DFFFFFF)',
    'Color(0x2B999999)',
    'Color(0x26FFFFFF)',
    'Color(0x0A000000)',
    'Color(0xFFFFFCF7)',
  },
};

/// Legacy roles that must never be read directly by a migrated screen again.
const _bannedLegacyRoles = <String>[
  'AppColors.darkText',
  'AppColors.itemSurface',
  'AppColors.mediumGray',
  'AppColors.canvas',
  'AppColors.primary',
  'AppColors.divider',
  'AppColors.error',
];

String _pathFor(String key) =>
    key.contains('/') ? key : '$_screensDir/$key';

void main() {
  final hexPattern = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');

  test('migrated screens only contain approved hardcoded colours', () {
    for (final entry in _allowedHexByFile.entries) {
      final file = File(_pathFor(entry.key));
      expect(file.existsSync(), isTrue, reason: 'missing ${entry.key}');

      final source = file.readAsStringSync();
      final found = hexPattern
          .allMatches(source)
          .map((match) => 'Color(0x${match.group(1)!.toUpperCase()})')
          .toSet();

      expect(
        found,
        entry.value,
        reason:
            '${entry.key} hardcoded colours changed. Move them to '
            'AppSemanticColors or update the reviewed allowlist.',
      );
    }
  });

  test('migrated screens never read the legacy colour roles directly', () {
    for (final key in _allowedHexByFile.keys) {
      final source = File(_pathFor(key)).readAsStringSync();
      for (final role in _bannedLegacyRoles) {
        expect(
          source.contains(role),
          isFalse,
          reason: '$key still reads $role; use AppSemanticColors instead.',
        );
      }
    }
  });

  test('every migrated screen resolves the semantic contract', () {
    for (final key in _allowedHexByFile.keys) {
      final source = File(_pathFor(key)).readAsStringSync();
      expect(
        source.contains('AppSemanticColors.of(context)'),
        isTrue,
        reason: '$key must read AppSemanticColors.of(context).',
      );
    }
  });
}
