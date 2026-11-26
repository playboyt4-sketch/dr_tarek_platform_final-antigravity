import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/core/widgets/animated_menu_button.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/archive/presentation/providers/archive_provider.dart';
import 'package:drtarek_dashboard/features/archive/presentation/screens/archive_screen.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/domain/repositories/auth_repository.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/domain/live_student.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';

class _FakeAuthRepository implements AuthRepository {
  int logoutCalls = 0;

  @override
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

class _FakeArchiveController implements ArchiveController {
  final List<String> calls = <String>[];

  @override
  Future<void> archiveLecture(String lectureId) async {
    calls.add('archiveLecture:$lectureId');
  }

  @override
  Future<void> archiveStudent(String studentId) async {
    calls.add('archiveStudent:$studentId');
  }

  @override
  Future<void> archiveSubject(String subjectId) async {
    calls.add('archiveSubject:$subjectId');
  }

  @override
  Future<void> permanentlyDelete({
    required String entityType,
    required String targetId,
  }) async {
    calls.add('purge:$entityType:$targetId');
  }

  @override
  Future<void> restoreLecture(String lectureId) async {
    calls.add('restoreLecture:$lectureId');
  }

  @override
  Future<void> restoreStudent(String studentId) async {
    calls.add('restoreStudent:$studentId');
  }

  @override
  Future<void> restoreSubject(String subjectId) async {
    calls.add('restoreSubject:$subjectId');
  }
}

const HomeAnalytics _analytics = HomeAnalytics(
  totalStudents: 10,
  activeToday: 2,
  weeklyActivity: <int>[1, 2, 1, 0, 3, 2, 1],
  grades: <GradeAnalytics>[
    GradeAnalytics(
      gradeKey: 'grade_one',
      total: 10,
      pending: 0,
      center: 6,
      guest: 4,
    ),
    GradeAnalytics(
      gradeKey: 'grade_two',
      total: 0,
      pending: 0,
      center: 0,
      guest: 0,
    ),
    GradeAnalytics(
      gradeKey: 'grade_three',
      total: 0,
      pending: 0,
      center: 0,
      guest: 0,
    ),
    GradeAnalytics(
      gradeKey: 'grade_four',
      total: 0,
      pending: 0,
      center: 0,
      guest: 0,
    ),
  ],
);

void main() {
  test('isLiveStudent excludes is_archived and is_deleted records', () {
    expect(
      isLiveStudent(<String, dynamic>{
        'is_archived': true,
        'account_status': 'active',
      }),
      isFalse,
    );
    expect(
      isLiveStudent(<String, dynamic>{
        'is_deleted': true,
        'account_status': 'active',
      }),
      isFalse,
    );
    expect(
      isLiveStudent(<String, dynamic>{
        'is_archived': false,
        'is_deleted': false,
        'account_status': 'disabled',
      }),
      isFalse,
    );
    expect(
      isLiveStudent(<String, dynamic>{
        'is_archived': false,
        'is_deleted': false,
        'account_status': 'active',
      }),
      isTrue,
    );
  });

  testWidgets('ArchiveScreen shows tabs, restores and permanently deletes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _FakeArchiveController fakeController = _FakeArchiveController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          archiveControllerProvider.overrideWithValue(fakeController),
          archivedStudentsProvider.overrideWith(
            (ref) => Stream.value(<ArchivedStudentItem>[
              ArchivedStudentItem(
                id: 'st_1',
                name: 'Mariam Adel',
                phone: '+201001112233',
                gradeKey: 'grade_one',
                isCenter: true,
                archivedAt: DateTime(2026, 11, 20, 14, 30),
              ),
            ]),
          ),
          archivedSubjectsProvider.overrideWith(
            (ref) => Stream.value(<ArchivedSubjectItem>[
              ArchivedSubjectItem(
                id: 'sub_1',
                title: 'Biology',
                gradeKey: 'grade_two',
                archivedAt: DateTime(2026, 11, 21, 9, 15),
              ),
            ]),
          ),
          archivedLecturesProvider.overrideWith(
            (ref) => Stream.value(<ArchivedLectureItem>[
              ArchivedLectureItem(
                id: 'lec_1',
                title: 'Cell Division',
                subjectId: 'sub_1',
                subjectTitle: 'Biology',
                archivedAt: DateTime(2026, 11, 22, 11, 0),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ArchiveScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Students (1)'), findsOneWidget);
    expect(find.text('Subjects (1)'), findsOneWidget);
    expect(find.text('Lectures (1)'), findsOneWidget);
    expect(find.text('Mariam Adel'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore Student'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(fakeController.calls, contains('restoreStudent:st_1'));

    await tester.tap(find.text('Subjects (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Biology'), findsOneWidget);

    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('permanently delete "Biology"'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete Permanently'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fakeController.calls, contains('purge:subject:sub_1'));
  });

  testWidgets('DashboardShell navigates to Archive and signs out with dialog',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _FakeAuthRepository fakeAuth = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          homeAnalyticsProvider.overrideWith((ref) => Future.value(_analytics)),
          archivedStudentsProvider.overrideWith(
            (ref) => Stream.value(const <ArchivedStudentItem>[]),
          ),
          archivedSubjectsProvider.overrideWith(
            (ref) => Stream.value(const <ArchivedSubjectItem>[]),
          ),
          archivedLecturesProvider.overrideWith(
            (ref) => Stream.value(const <ArchivedLectureItem>[]),
          ),
          gradeStudentsProvider('grade_one').overrideWith(
            (ref) => Future.value(
              const GradeStudentsData(
                gradeKey: 'grade_one',
                students: <GradeStudent>[],
                pendingCount: 0,
                breakdown: <PlanBreakdownRow>[],
                isFallback: false,
              ),
            ),
          ),
          gradeSubjectsProvider('grade_one').overrideWith(
            (ref) => Stream.value(const <SubjectOption>[]),
          ),
        ],
        child: const MaterialApp(home: DashboardShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Open menu -> navigate to Archive.
    await tester.tap(find.byType(TheMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('No archived students.'), findsOneWidget);

    // Open menu -> tap Sign Out -> confirm dialog -> calls logout.
    await tester.tap(find.byType(TheMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Are you sure you want to sign out'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await tester.pumpAndSettle();

    expect(fakeAuth.logoutCalls, 1);
  });
}
