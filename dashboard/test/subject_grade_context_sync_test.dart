import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';
import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/subject_details_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/grade_nav_bar.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/grade_theme.dart';

// Fixtures: one subject per grade. Each SubjectOption carries its owning
// grade in [SubjectOption.gradeKey] — the source of truth for the grade
// context when Subject Details is opened.
const SubjectOption _g1Subject = SubjectOption(
  id: 'sub-g1',
  title: 'G1 Math',
  gradeKey: 'grade_one',
);
const SubjectOption _g3Subject = SubjectOption(
  id: 'sub-g3',
  title: 'G3 Science',
  gradeKey: 'grade_three',
);
const SubjectOption _g4Subject = SubjectOption(
  id: 'sub-g4',
  title: 'G4 History',
  gradeKey: 'grade_four',
);

GradeStudentsData _studentsFor(String gradeKey) => GradeStudentsData(
      gradeKey: gradeKey,
      students: const <GradeStudent>[],
      pendingCount: 0,
      breakdown: const <PlanBreakdownRow>[
        PlanBreakdownRow(label: 'Free', count: 0, share: 0),
        PlanBreakdownRow(label: 'PRO', count: 0, share: 0),
        PlanBreakdownRow(label: 'MAX', count: 0, share: 0),
        PlanBreakdownRow(label: 'Guest', count: 0, share: 0),
      ],
      isFallback: false,
    );

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  const List<SubjectOption> subjects = <SubjectOption>[
    _g1Subject,
    _g3Subject,
    _g4Subject,
  ];

  await tester.pumpWidget(
    ProviderScope(
      // NOTE: the list is built inline so the override types are inferred
      // contextually (`Override` is not part of flutter_riverpod's public
      // export surface).
      overrides: [
        gradeStudentsProvider('grade_one')
            .overrideWith((ref) => Future.value(_studentsFor('grade_one'))),
        gradeStudentsProvider('grade_three').overrideWith(
            (ref) => Future.value(_studentsFor('grade_three'))),
        gradeStudentsProvider('grade_four')
            .overrideWith((ref) => Future.value(_studentsFor('grade_four'))),
        gradeSubjectsProvider('grade_one').overrideWith(
            (ref) => Stream.value(const <SubjectOption>[_g1Subject])),
        gradeSubjectsProvider('grade_three').overrideWith(
            (ref) => Stream.value(const <SubjectOption>[_g3Subject])),
        gradeSubjectsProvider('grade_four').overrideWith(
            (ref) => Stream.value(const <SubjectOption>[_g4Subject])),
        for (final SubjectOption subject in subjects)
          subjectDetailsProvider(subject.id).overrideWith(
            (ref) => Stream.value(
              SubjectDetails(
                id: subject.id,
                title: subject.title,
                isVisible: true,
              ),
            ),
          ),
        for (final SubjectOption subject in subjects)
          for (final SubjectContentTab tab in SubjectContentTab.values)
            tabLecturesProvider((subjectId: subject.id, tab: tab))
                .overrideWith(
              (ref) => Stream.value(const <SubjectLecture>[]),
            ),
      ],
      child: const MaterialApp(home: DashboardShell()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _goToGradeViaMenu(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel('Open menu'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(DashboardFullMenu),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSubjectsTab(WidgetTester tester) async {
  await tester.tap(find.text('Subjects'));
  await tester.pumpAndSettle();
}

Future<void> _tapSubjectCard(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Taps a grade pill inside the visible top [GradeNavBar].
Future<void> _tapGradePill(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(GradeNavBar),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

SubjectDetailsScreen _detailsOf(WidgetTester tester) =>
    tester.widget<SubjectDetailsScreen>(find.byType(SubjectDetailsScreen));

String _navGradeOf(WidgetTester tester) =>
    tester.widget<GradeNavBar>(find.byType(GradeNavBar)).gradeKey;

/// Asserts the full synchronization chain for one opened subject:
/// subject ownership → selected grade → GradeTheme → active nav pill.
void _expectGradeSync(
  WidgetTester tester, {
  required SubjectOption subject,
  required String expectedGradeKey,
}) {
  final SubjectDetailsScreen details = _detailsOf(tester);
  // 1. The opened subject belongs to the expected grade.
  expect(subject.gradeKey, expectedGradeKey);
  expect(details.subjectId, subject.id);
  // 2. Selected grade equals the subject's grade.
  expect(
    details.gradeKey,
    GradeTheme.fromKey(expectedGradeKey).gradeId,
    reason: 'selectedGrade must equal subject.grade',
  );
  // 3. Active Grade Navigation pill equals the subject's grade.
  expect(
    _navGradeOf(tester),
    GradeTheme.fromKey(expectedGradeKey).gradeId,
    reason: 'active Grade Navigation pill must equal subject.grade',
  );
  // 4. GradeTheme corresponds to the subject's grade.
  expect(
    GradeTheme.fromKey(details.gradeKey).gradeId,
    GradeTheme.fromKey(expectedGradeKey).gradeId,
    reason: 'GradeTheme must correspond to subject.grade',
  );
}

void main() {
  group('Subject Details grade-context synchronization', () {
    testWidgets(
        'Grade 1 → Subject → Grade 3 → Subject → Grade 4 → Subject stays synchronized',
        (WidgetTester tester) async {
      await _pumpShell(tester);

      // 1-3. Open Grade 1 → Subjects → Grade 1 subject.
      await _goToGradeViaMenu(tester, 'Grade One');
      await _openSubjectsTab(tester);
      await _tapSubjectCard(tester, 'G1 Math');
      _expectGradeSync(tester,
          subject: _g1Subject, expectedGradeKey: 'grade_one');

      // 4-5. Switch top Grade Navigation to Grade 3 → open Grade 3 subject.
      await _tapGradePill(tester, 'Grade Three');
      await _tapSubjectCard(tester, 'G3 Science');
      _expectGradeSync(tester,
          subject: _g3Subject, expectedGradeKey: 'grade_three');

      // 6-7. Switch top Grade Navigation to Grade 4 → open Grade 4 subject.
      await _tapGradePill(tester, 'Grade Four');
      await _tapSubjectCard(tester, 'G4 History');
      _expectGradeSync(tester,
          subject: _g4Subject, expectedGradeKey: 'grade_four');
    });

    testWidgets(
        'subject tap after an in-list grade switch uses the subject grade, not the stale shell grade',
        (WidgetTester tester) async {
      await _pumpShell(tester);

      // Shell grade context is Grade One; switch grades inside the list
      // (GradeStudentsScreen owns a local grade state that never notifies
      // the shell) and open a Grade 4 subject. Pre-fix this opened
      // Subject Details with Grade One as the active grade.
      await _goToGradeViaMenu(tester, 'Grade One');
      await _openSubjectsTab(tester);
      await _tapGradePill(tester, 'Grade Four');
      expect(find.text('G4 History'), findsOneWidget);
      await _tapSubjectCard(tester, 'G4 History');
      _expectGradeSync(tester,
          subject: _g4Subject, expectedGradeKey: 'grade_four');

      // Exact reported symptom in reverse: from Grade 4 details back to
      // the list, switch in-list to Grade 3 (shell still Grade 4), open
      // the Grade 3 subject — details must follow the subject to Grade 3.
      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();
      await _tapGradePill(tester, 'Grade Three');
      expect(find.text('G3 Science'), findsOneWidget);
      await _tapSubjectCard(tester, 'G3 Science');
      _expectGradeSync(tester,
          subject: _g3Subject, expectedGradeKey: 'grade_three');
    });

    testWidgets(
        'directly opening Grade 3 / Grade 4 subjects selects their grade',
        (WidgetTester tester) async {
      await _pumpShell(tester);

      await _goToGradeViaMenu(tester, 'Grade Three');
      await _openSubjectsTab(tester);
      await _tapSubjectCard(tester, 'G3 Science');
      _expectGradeSync(tester,
          subject: _g3Subject, expectedGradeKey: 'grade_three');

      await _goToGradeViaMenu(tester, 'Grade Four');
      await _openSubjectsTab(tester);
      await _tapSubjectCard(tester, 'G4 History');
      _expectGradeSync(tester,
          subject: _g4Subject, expectedGradeKey: 'grade_four');
    });

    testWidgets('grade switching still works normally', (
      WidgetTester tester,
    ) async {
      await _pumpShell(tester);

      // Menu navigation between grades.
      await _goToGradeViaMenu(tester, 'Grade One');
      await _openSubjectsTab(tester);
      expect(find.text('G1 Math'), findsOneWidget);

      // In-list grade pills switch the visible subject list.
      await _tapGradePill(tester, 'Grade Three');
      expect(find.text('G3 Science'), findsOneWidget);
      expect(find.text('G1 Math'), findsNothing);

      await _tapGradePill(tester, 'Grade Four');
      expect(find.text('G4 History'), findsOneWidget);
      expect(find.text('G3 Science'), findsNothing);

      // Grade nav inside Subject Details still navigates to grade lists.
      await _tapSubjectCard(tester, 'G4 History');
      expect(find.byType(SubjectDetailsScreen), findsOneWidget);
      await _tapGradePill(tester, 'Grade One');
      expect(find.byType(SubjectDetailsScreen), findsNothing);
      await _openSubjectsTab(tester);
      expect(find.text('G1 Math'), findsOneWidget);
    });
  });
}
