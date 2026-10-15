import 'package:drtarek_dashboard/features/applications/domain/grade.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the canonical grade contract for every grade-filtered
/// Dashboard surface (Grade students table, pending counts, home
/// analytics): every known spelling must fold to `canonicalGradeKeys`
/// so a persisted `users.grade` is never excluded by spelling.
void main() {
  group('normalizeGradeKey - canonical source of truth', () {
    test('canonical keys are stable', () {
      for (final key in canonicalGradeKeys) {
        expect(normalizeGradeKey(key), key, reason: key);
      }
    });

    test('legacy digit spellings fold to canonical keys', () {
      expect(normalizeGradeKey('grade_1'), 'grade_one');
      expect(normalizeGradeKey('grade_2'), 'grade_two');
      expect(normalizeGradeKey('grade_3'), 'grade_three');
      expect(normalizeGradeKey('grade_4'), 'grade_four');
      expect(normalizeGradeKey('2'), 'grade_two');
      expect(normalizeGradeKey('Grade 3'), 'grade_three');
    });

    test('grade_two equals grade_2 after normalization (list filter)', () {
      expect(
        normalizeGradeKey('grade_two'),
        normalizeGradeKey('grade_2'),
      );
    });

    test('all four canonical keys match their digit spellings', () {
      const pairs = {
        'grade_one': 'grade_1',
        'grade_two': 'grade_2',
        'grade_three': 'grade_3',
        'grade_four': 'grade_4',
      };
      for (final entry in pairs.entries) {
        expect(
          normalizeGradeKey(entry.key),
          normalizeGradeKey(entry.value),
          reason: '${entry.key} must match ${entry.value}',
        );
      }
    });

    test('every normalized output is a canonical key (home-stats invariant)', () {
      const inputs = [
        'grade_one',
        'grade_two',
        'grade_three',
        'grade_four',
        'grade_1',
        'grade_2',
        'grade_3',
        'grade_4',
        'Grade Two',
        'الفرقة الثالثة',
      ];
      for (final input in inputs) {
        final normalized = normalizeGradeKey(input);
        expect(normalized, isNotNull, reason: input);
        expect(canonicalGradeKeys, contains(normalized), reason: input);
      }
    });

    test('different grades never match after normalization', () {
      expect(
        normalizeGradeKey('grade_two'),
        isNot(normalizeGradeKey('grade_three')),
      );
      expect(
        normalizeGradeKey('grade_2'),
        isNot(normalizeGradeKey('grade_3')),
      );
    });

    test('unparseable input maps to null', () {
      expect(normalizeGradeKey(null), isNull);
      expect(normalizeGradeKey(''), isNull);
      expect(normalizeGradeKey('nonsense'), isNull);
    });
  });
}
