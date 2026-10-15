import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;
import 'package:drtarek_dashboard/features/students/domain/repositories/subject_access_repository.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake repository: FREE grants fail exactly like the server does when
/// `system_settings.free_plan_enabled == false`; PRO/MAX succeed; every
/// attempted subject is recorded in call order.
class _FakeSubjectAccessRepository implements SubjectAccessRepository {
  final List<String> grantCalls = <String>[];
  final List<String> accessCalls = <String>[];

  @override
  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool restore = false,
  }) async {
    accessCalls.add(subjectId);
  }

  @override
  Future<void> removeSubject({
    required String studentId,
    required String subjectId,
    required bool enabled,
  }) async {
    accessCalls.add(subjectId);
  }

  @override
  Future<void> grantAccessWithPlan({
    required String studentId,
    required String subjectId,
    required String studentType,
    required String plan,
  }) async {
    grantCalls.add(subjectId);
    if (plan == 'free') {
      throw const DecisionFailure(
        'Free Plan is disabled in system settings.',
      );
    }
  }

  @override
  Future<bool> isFreePlanEnabled() async => false;
}

const Map<String, String> _titles = <String, String>{
  'sub_free': 'مادة مجانية',
  'sub_pro': 'شركات الأشخاص',
  'sub_max': 'محاسبة متوسطة',
};

List<NewStudentSubject> _batch() => const <NewStudentSubject>[
      NewStudentSubject(subjectId: 'sub_free', enabled: true, plan: 'free'),
      NewStudentSubject(subjectId: 'sub_pro', enabled: true, plan: 'pro'),
      NewStudentSubject(subjectId: 'sub_max', enabled: true, plan: 'max'),
    ];

void main() {
  group('addSubjects per-subject isolation', () {
    test(
        'FREE-when-disabled fails but PRO and MAX are still attempted '
        '(no loop-abort, no silent drop)', () async {
      final fake = _FakeSubjectAccessRepository();
      final controller = StudentProfileSubjectsController(fake);

      final List<SubjectGrantOutcome> outcomes =
          await controller.addSubjects(
        studentId: 'stu_001',
        isCenter: true,
        subjects: _batch(),
        alreadyRegistered: const <String>{},
        subjectTitles: _titles,
      );

      // All three subjects were attempted — nothing after the failure
      // was skipped.
      expect(fake.grantCalls, <String>['sub_free', 'sub_pro', 'sub_max']);
      expect(outcomes, hasLength(3));

      // The FREE row reports the server message honestly...
      expect(outcomes[0].success, isFalse);
      expect(
        outcomes[0].errorMessage,
        'Free Plan is disabled in system settings.',
      );
      expect(outcomes[0].subjectName, 'مادة مجانية');

      // ...while PRO and MAX succeed.
      expect(outcomes[1].success, isTrue);
      expect(outcomes[1].errorMessage, isNull);
      expect(outcomes[2].success, isTrue);
      expect(outcomes[2].errorMessage, isNull);
    });

    test('disabled (OFF) rows use the access-only path, still isolated',
        () async {
      final fake = _FakeSubjectAccessRepository();
      final controller = StudentProfileSubjectsController(fake);

      final List<SubjectGrantOutcome> outcomes =
          await controller.addSubjects(
        studentId: 'stu_001',
        isCenter: true,
        subjects: const <NewStudentSubject>[
          NewStudentSubject(
              subjectId: 'sub_off', enabled: false, plan: 'free'),
          NewStudentSubject(
              subjectId: 'sub_pro', enabled: true, plan: 'pro'),
        ],
        alreadyRegistered: const <String>{},
        subjectTitles: const <String, String>{
          'sub_off': 'مادة متوقفة',
          'sub_pro': 'شركات الأشخاص',
        },
      );

      expect(fake.accessCalls, <String>['sub_off']);
      expect(fake.grantCalls, <String>['sub_pro']);
      expect(outcomes.every((o) => o.success), isTrue);
    });

    test('already-registered subjects are skipped without a call',
        () async {
      final fake = _FakeSubjectAccessRepository();
      final controller = StudentProfileSubjectsController(fake);

      final List<SubjectGrantOutcome> outcomes =
          await controller.addSubjects(
        studentId: 'stu_001',
        isCenter: true,
        subjects: _batch(),
        alreadyRegistered: const <String>{'sub_free'},
        subjectTitles: _titles,
      );

      expect(fake.grantCalls, <String>['sub_pro', 'sub_max']);
      expect(
        outcomes.map((o) => o.subjectId),
        <String>['sub_pro', 'sub_max'],
      );
    });
  });
}
