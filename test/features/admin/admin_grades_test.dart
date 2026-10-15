import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/admin/domain/admin_grades.dart';

void main() {
  group('normalizeAdminGradeKey (§13)', () {
    test('canonicalizes both historical spellings', () {
      expect(normalizeAdminGradeKey('grade_one'), 'grade_one');
      expect(normalizeAdminGradeKey('grade_2'), 'grade_two');
      expect(normalizeAdminGradeKey(' Grade 3 '), 'grade_three');
      expect(normalizeAdminGradeKey('4'), 'grade_four');
      expect(normalizeAdminGradeKey(null), isNull);
      expect(normalizeAdminGradeKey('nonsense'), isNull);
    });
  });

  group('gradeLabel - canonical Arabic display labels', () {
    test('all four canonical keys resolve', () {
      expect(gradeLabel('grade_one'), 'الفرقة الأولى');
      expect(gradeLabel('grade_two'), 'الفرقة الثانية');
      expect(gradeLabel('grade_three'), 'الفرقة الثالثة');
      expect(gradeLabel('grade_four'), 'الفرقة الرابعة');
    });
  });

  group('filter normalization - canonical vs legacy comparison', () {
    // Mirrors the watchStudents comparison:
    // normalizeAdminGradeKey(grade) == normalizeAdminGradeKey(gradeKey).
    test('grade_three matches grade_3 (reported production case)', () {
      expect(
        normalizeAdminGradeKey('grade_three'),
        normalizeAdminGradeKey('grade_3'),
      );
    });

    test('all four canonical keys match their legacy digit spellings', () {
      const pairs = {
        'grade_one': 'grade_1',
        'grade_two': 'grade_2',
        'grade_three': 'grade_3',
        'grade_four': 'grade_4',
      };
      for (final entry in pairs.entries) {
        expect(
          normalizeAdminGradeKey(entry.key),
          normalizeAdminGradeKey(entry.value),
          reason: '${entry.key} must match ${entry.value}',
        );
      }
    });

    test('different grades never match after normalization', () {
      expect(
        normalizeAdminGradeKey('grade_three'),
        isNot(normalizeAdminGradeKey('grade_one')),
      );
      expect(
        normalizeAdminGradeKey('grade_3'),
        isNot(normalizeAdminGradeKey('grade_1')),
      );
    });

    test('unparseable filter matches nothing persisted', () {
      // normalizeAdminGradeKey(null) is null, but every persisted grade
      // normalizes to a canonical key, so an unknown filter excludes all
      // real students instead of leaking them into the wrong list.
      for (final canonical in kCanonicalGradeKeys) {
        expect(normalizeAdminGradeKey(canonical), isNotNull);
        expect(
          normalizeAdminGradeKey(canonical) == normalizeAdminGradeKey('nonsense'),
          isFalse,
        );
      }
    });
  });

  group('priorGradeKeysFor (FINAL_DECISIONS §13)', () {
    test('grade_two student gets exactly grade_one subjects', () {
      expect(priorGradeKeysFor('grade_two'), ['grade_one']);
    });

    test('grade_four student gets grades one..three in order', () {
      expect(
        priorGradeKeysFor('grade_four'),
        ['grade_one', 'grade_two', 'grade_three'],
      );
    });

    test('grade_one has NO prior grades — no UI may render', () {
      expect(priorGradeKeysFor('grade_one'), isEmpty);
    });

    test('unknown or unset grades have no prior-term UI either', () {
      expect(priorGradeKeysFor(null), isEmpty);
      expect(priorGradeKeysFor(''), isEmpty);
      expect(priorGradeKeysFor('legacy_value'), isEmpty);
    });
  });

  group('buildSubjectAccessPayload (approveStudent contract)', () {
    test('emits {subjectId, enabled} objects with no duplicates', () {
      final payload = buildSubjectAccessPayload(
        primarySubjectIds: const ['s1', 's2'],
        priorGradeSubjectIds: const ['s3'],
      );

      expect(payload, [
        {'subjectId': 's1', 'enabled': true},
        {'subjectId': 's2', 'enabled': true},
        {'subjectId': 's3', 'enabled': true},
      ]);
    });

    test('primary wins when the same subject appears in both lists', () {
      final payload = buildSubjectAccessPayload(
        primarySubjectIds: const ['s1', 's2'],
        priorGradeSubjectIds: const ['s2', 's3'],
      );

      expect(payload.map((e) => e['subjectId']), ['s1', 's2', 's3']);
    });

    test('skips empty ids and tolerates empty input', () {
      expect(buildSubjectAccessPayload(primarySubjectIds: const []), isEmpty);
      expect(
        buildSubjectAccessPayload(primarySubjectIds: const ['']),
        isEmpty,
      );
    });
  });
}
