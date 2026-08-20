import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/repositories/dashboard_repository.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:dr_tarek_platform/features/student_home/presentation/screens/student_home_screen.dart';

class _FakeDashboardRepository implements DashboardRepository {
  List<DashboardSubject> subjects = const [];

  @override
  Future<List<DashboardSubject>> getAccessibleSubjects({
    required String studentId,
  }) async =>
      subjects;
}

AuthUser _student() {
  return const AuthUser(
    id: 'student-1',
    fullName: 'Tarek El Araby',
    phoneNumber: '01000000000',
    role: 'student',
    studentType: 'public_student',
    grade: 'grade_one',
    approvalStatus: 'approved',
    accountStatus: 'active',
  );
}

Future<void> _pumpHome(
  WidgetTester tester,
  _FakeDashboardRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardSubjectsProvider.overrideWith(
          (ref) async => repository.subjects,
        ),
        studentPlanKeyProvider.overrideWith((ref, studentId) async => null),
      ],
      child: MaterialApp(home: StudentHomeScreen(user: _student())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the greeting with the first name and 3-tab bottom nav', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository();
    await _pumpHome(tester, repository);

    expect(find.text('Hi, Tarek'), findsOneWidget);

    final navBar = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(navBar.items.length, 3);
    expect(navBar.items[0].label, 'Home');
    expect(navBar.items[1].label, 'Chat');
    expect(navBar.items[2].label, 'Notifications');
  });

  testWidgets('renders one pill button per enabled subject with status line', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository()
      ..subjects = const [
        DashboardSubject(
          id: 'subject-1',
          title: 'الرياضيات',
          displayOrder: 1,
          subscriptionState: DashboardSubscriptionState.active,
        ),
        DashboardSubject(
          id: 'subject-2',
          title: 'الفيزياء',
          displayOrder: 2,
          subscriptionState: DashboardSubscriptionState.disciplinaryDisabled,
        ),
      ];
    await _pumpHome(tester, repository);

    expect(find.text('الرياضيات'), findsOneWidget);
    expect(find.text('الفيزياء'), findsOneWidget);
    expect(find.text('اشتراك نشط'), findsOneWidget);
    expect(find.text('موقوف تأديبياً'), findsOneWidget);
  });

  testWidgets('shows the empty-state message when no subjects are enabled', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository();
    await _pumpHome(tester, repository);

    expect(find.textContaining('لا توجد مواد مفعّلة'), findsOneWidget);
  });

  testWidgets('background color follows the student grade identity token', (
    tester,
  ) async {
    final repository = _FakeDashboardRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardSubjectsProvider.overrideWith(
            (ref) async => repository.subjects,
          ),
          studentPlanKeyProvider.overrideWith((ref, studentId) async => null),
        ],
        child: MaterialApp(
          home: StudentHomeScreen(
            user: const AuthUser(
              id: 'student-2',
              fullName: 'Sara Ahmed',
              phoneNumber: '01000000001',
              role: 'student',
              studentType: 'center_student',
              grade: 'grade_three',
              approvalStatus: 'approved',
              accountStatus: 'active',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF34A853));
    expect(find.text('Hi, Sara'), findsOneWidget);
  });
}
