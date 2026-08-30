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
