import 'dart:typed_data';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/profile/domain/repositories/profile_repository.dart';
import 'package:dr_tarek_platform/features/profile/domain/use_cases/update_student_grade_use_case.dart';
import 'package:dr_tarek_platform/features/profile/presentation/screens/grade_one_profile_overview_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand fake: records the grade-update payload and optionally fails,
/// standing in for the `updateStudentGrade` callable transport.
class FakeProfileRepository implements ProfileRepository {
  String? lastStudentId;
  String? lastGrade;
  int updateCalls = 0;
  Object? failure;

  @override
  Future<AuthUser> getStudentProfile(String studentId) {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateProfilePhotoUrl({
    required String userId,
    required String url,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateFullName({
    required String userId,
    required String fullName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateStudentGrade({
    required String studentId,
    required String grade,
  }) async {
    updateCalls++;
    lastStudentId = studentId;
    lastGrade = grade;
    final error = failure;
    if (error != null) throw error;
  }
}

void main() {
  group('canonicalGradeForLabel - only canonical keys cross the repo boundary', () {
    test('UI labels map to canonical keys', () {
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade One'),
        'grade_one',
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade Two'),
        'grade_two',
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade Three'),
        'grade_three',
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade Four'),
        'grade_four',
      );
    });

    test('a UI label is never returned verbatim', () {
      for (final label in const [
        'Grade One',
        'Grade Two',
        'Grade Three',
        'Grade Four',
      ]) {
        final canonical =
            GradeOneProfileOverviewScreen.canonicalGradeForLabel(label);
        expect(canonical, isNot(label));
        expect(canonical, startsWith('grade_'));
      }
    });

    test('legacy spellings normalize to canonical keys', () {
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('grade_2'),
        'grade_two',
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade Two'),
        'grade_two',
      );
    });

    test('unknown or null input maps to null (caller rejects)', () {
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel('Grade Five'),
        isNull,
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel(null),
        isNull,
      );
      expect(
        GradeOneProfileOverviewScreen.canonicalGradeForLabel(''),
        isNull,
      );
    });
  });

  group('gradeLabelForKey - canonical keys render as overview labels', () {
    test('canonical keys map to labels', () {
      expect(
        GradeOneProfileOverviewScreen.gradeLabelForKey('grade_one'),
        'Grade One',
      );
      expect(
        GradeOneProfileOverviewScreen.gradeLabelForKey('grade_two'),
        'Grade Two',
      );
      expect(
        GradeOneProfileOverviewScreen.gradeLabelForKey('grade_three'),
        'Grade Three',
      );
      expect(
        GradeOneProfileOverviewScreen.gradeLabelForKey('grade_four'),
        'Grade Four',
      );
    });
  });

  group('isGradeUnchanged - same-grade no-op skips the backend', () {
    test('identical grade reports unchanged', () {
      expect(
        GradeOneProfileOverviewScreen.isGradeUnchanged(
          currentGradeKey: 'grade_two',
          selectedLabel: 'Grade Two',
        ),
        isTrue,
      );
    });

    test('legacy spelling of the same grade reports unchanged', () {
      expect(
        GradeOneProfileOverviewScreen.isGradeUnchanged(
          currentGradeKey: 'grade_2',
          selectedLabel: 'Grade Two',
        ),
        isTrue,
      );
    });

    test('different grade reports changed', () {
      expect(
        GradeOneProfileOverviewScreen.isGradeUnchanged(
          currentGradeKey: 'grade_one',
          selectedLabel: 'Grade Two',
        ),
        isFalse,
      );
    });
  });

  group('UpdateStudentGradeUseCase - thin delegation, no logic', () {
    test('forwards the real studentId and canonical grade untouched', () async {
      final fake = FakeProfileRepository();
      final useCase = UpdateStudentGradeUseCase(fake);

      await useCase.execute(studentId: 'stu_001', grade: 'grade_two');

      expect(fake.updateCalls, 1);
      expect(fake.lastStudentId, 'stu_001');
      expect(fake.lastGrade, 'grade_two');
    });

    test('callable failures (e.g. permission-denied) propagate unwrapped '
        'for UI mapping via friendlyFunctionErrorMessage', () async {
      final failure = StateError('permission-denied stand-in');
      final fake = FakeProfileRepository()..failure = failure;
      final useCase = UpdateStudentGradeUseCase(fake);

      await expectLater(
        useCase.execute(studentId: 'stu_001', grade: 'grade_two'),
        throwsA(same(failure)),
      );
      // The use case never swallows or rewraps server errors: the Save
      // path surfaces them with friendlyFunctionErrorMessage, whose
      // permission-denied mapping is covered in
      // test/core/errors/friendly_error_message_test.dart.
      expect(fake.updateCalls, 1);
    });
  });
}
