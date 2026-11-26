import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/membership/presentation/widgets/center_phone_actions.dart';
import 'package:dr_tarek_platform/features/profile/domain/repositories/profile_repository.dart';
import 'package:dr_tarek_platform/features/profile/presentation/providers/profile_providers.dart';
import 'package:dr_tarek_platform/features/profile/presentation/screens/student_profile_screen.dart';
import 'package:dr_tarek_platform/features/profile/presentation/widgets/profile_edit_sheet.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopProfileRepository implements ProfileRepository {
  @override
  Future<AuthUser> getStudentProfile(String studentId) =>
      throw UnimplementedError();

  @override
  Future<String> uploadProfilePhoto({
    required String userId,
    required bytes,
    required String fileName,
  }) => throw UnimplementedError();

  @override
  Future<void> updateProfilePhotoUrl({
    required String userId,
    required String url,
  }) => throw UnimplementedError();

  @override
  Future<void> updateStudentGrade({
    required String studentId,
    required String grade,
  }) => throw UnimplementedError();

  @override
  Future<void> updateFullName({
    required String userId,
    required String fullName,
  }) async {}
}

const _student = AuthUser(
  id: 'student-1',
  fullName: 'Mai Helmy',
  phoneNumber: '01098173500',
  role: 'student',
  studentType: 'center_student',
  grade: 'grade_four',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

void main() {
  testWidgets(
    'shows Upgrade button for Free/Pro subjects (not Max) and opens sheet with 3 phone actions',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardSubjectsProvider.overrideWith(
              (ref) => Stream.value(const <DashboardSubject>[
                DashboardSubject(
                  id: 'sub-free',
                  title: 'محاسبة تكاليف',
                  planKey: 'free',
                  displayOrder: 1,
                ),
                DashboardSubject(
                  id: 'sub-pro',
                  title: 'مالية متقدمة',
                  planKey: 'pro',
                  displayOrder: 2,
                ),
                DashboardSubject(
                  id: 'sub-max',
                  title: 'محاسبة حكومية',
                  planKey: 'max',
                  displayOrder: 3,
                ),
              ]),
            ),
            profileRepositoryProvider.overrideWithValue(
              _NoopProfileRepository(),
            ),
            studentDevicesProvider('student-1').overrideWith(
              (ref) => Stream.value(const <StudentDevice>[]),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: StudentProfileScreen(user: _student),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Free and Pro subjects display Upgrade; Max does not.
      expect(
        find.byKey(const ValueKey('upgrade_subject_sub-free')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('upgrade_subject_sub-pro')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('upgrade_subject_sub-max')),
        findsNothing,
      );

      // Tapping Upgrade opens bottom sheet with CenterPhoneActions (Copy, Call, WhatsApp).
      await tester.tap(find.byKey(const ValueKey('upgrade_subject_sub-pro')));
      await tester.pumpAndSettle();

      expect(find.text('ترقية اشتراك المادة'), findsOneWidget);
      expect(find.byType(CenterPhoneActions), findsOneWidget);
      expect(find.byKey(const ValueKey('center_phone_copy_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('center_phone_call_btn')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('center_phone_whatsapp_btn')),
        findsOneWidget,
      );
    },
  );
}
