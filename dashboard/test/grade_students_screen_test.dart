import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_students_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/scoped_search_bar.dart';

const GradeStudentsData _gradeOneData = GradeStudentsData(
  gradeKey: 'grade_one',
  students: <GradeStudent>[
    GradeStudent(
      id: 'a1',
      name: 'Ahmed gamal mousa',
      isCenter: true,
      planSummary: StudentPlanSummary(subjects: 2, free: 1, pro: 1),
      isActive: true,
      lastSignIn: '12/8/2026',
    ),
    GradeStudent(
      id: 'a2',
      name: 'Mariam adel samy',
      isCenter: true,
      planSummary: StudentPlanSummary(subjects: 1, free: 1),
      isActive: true,
      lastSignIn: '11/8/2026',
    ),
    GradeStudent(
      id: 'a3',
      name: 'Omar khaled hassan',
      isCenter: false,
      planSummary: StudentPlanSummary.empty,
      isActive: false,
      lastSignIn: '9/8/2026',
    ),
  ],
  pendingCount: 11,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Students with FREE', count: 2, share: 67),
    PlanBreakdownRow(label: 'Students with PRO', count: 1, share: 33),
    PlanBreakdownRow(label: 'Students with MAX', count: 0, share: 0),
    PlanBreakdownRow(label: 'No active plan', count: 1, share: 33),
  ],
  isFallback: false,
);

const GradeStudentsData _gradeThreeData = GradeStudentsData(
  gradeKey: 'grade_three',
  students: <GradeStudent>[
    GradeStudent(
      id: 'b1',
      name: 'Salma mohamed ali',
      isCenter: true,
      planSummary: StudentPlanSummary(subjects: 1, max: 1),
      isActive: true,
      lastSignIn: '10/8/2026',
    ),
    GradeStudent(
      id: 'b2',
      name: 'Nour eldin sami',
      isCenter: false,
      planSummary: StudentPlanSummary(subjects: 2, pro: 1, max: 1),
      isActive: true,
      lastSignIn: '9/8/2026',
    ),
  ],
  pendingCount: 5,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Students with FREE', count: 0, share: 0),
    PlanBreakdownRow(label: 'Students with PRO', count: 1, share: 50),
    // b1 AND b2 both hold MAX: buckets overlap by design (150% total).
    PlanBreakdownRow(label: 'Students with MAX', count: 2, share: 100),
    PlanBreakdownRow(label: 'No active plan', count: 0, share: 0),
  ],
  isFallback: false,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  String gradeKey = 'grade_one',
  List<SubjectOption> subjects = const <SubjectOption>[],
  void Function(String)? onReviewPending,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (gradeKey == 'grade_one')
          gradeStudentsProvider('grade_one')
              .overrideWith((ref) => Future.value(_gradeOneData)),
        gradeStudentsProvider('grade_three')
            .overrideWith((ref) => Future.value(_gradeThreeData)),
        gradeSubjectsProvider(gradeKey)
            .overrideWith((ref) => Stream.value(subjects)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GradeStudentsScreen(
            initialGradeKey: gradeKey,
            onReviewPending: onReviewPending,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ScopedSearchBar', () {
    testWidgets('renders closed state with name placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: ScopedSearchBar())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Search by Name...'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('opens dropdown and switches scope with placeholder',
        (WidgetTester tester) async {
      SearchScope? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScopedSearchBar(
                onScopeChanged: (SearchScope scope) => selected = scope,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('scope-selector')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('scope-option-type')));
      await tester.pumpAndSettle();
      expect(selected, SearchScope.type);
      expect(find.text('Search by Type (Center / Guest)...'), findsOneWidget);
    });

    testWidgets('emits search text changes', (WidgetTester tester) async {
      String? query;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScopedSearchBar(
                onSearchChanged: (String value) => query = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ahmed');
      expect(query, 'ahmed');
    });
  });

  group('GradeStudentsScreen', () {
    testWidgets('renders full Figma composition with live data',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      expect(find.text('Grade One'), findsWidgets);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Subjects'), findsOneWidget);
      expect(find.text('Total Students'), findsOneWidget);
      expect(find.text('450'), findsNothing);
      expect(find.text('Students with FREE: 2 (67%)'), findsOneWidget);
      expect(find.text('Students with PRO: 1 (33%)'), findsOneWidget);
      expect(find.text('Students with MAX: 0 (0%)'), findsOneWidget);
      expect(find.text('No active plan: 1 (33%)'), findsOneWidget);
      expect(
        find.text(
          'Share of 3 students; a student with several tiers counts in each.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review Pending Requests'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('Search by Name...'), findsOneWidget);
      for (final String header in <String>[
        'No.',
        'Student Name',
        'Type',
        'Plan',
        'Status',
        'Last Sign in',
        'Action',
      ]) {
        expect(find.text(header), findsOneWidget);
      }
      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      // Honest per-student summary cell (Option B): true distribution,
      // never a collapsed single value; empty state is explicit.
      expect(find.text('2 subjects'), findsOneWidget);
      expect(find.text('1 FREE · 1 PRO'), findsOneWidget);
      expect(find.text('1 subject'), findsOneWidget);
      expect(find.text('1 FREE'), findsOneWidget);
      expect(find.text('No active plan'), findsWidgets);
      expect(find.text('01.'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('View'), findsWidgets);
    });

    testWidgets('total shows live count from provider',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      // Live data overrides the 450 fallback total.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('search filters rows by scope',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'mariam');
      await tester.pumpAndSettle();
      expect(find.text('Mariam adel samy'), findsOneWidget);
      expect(find.text('Ahmed gamal mousa'), findsNothing);

      // Switch to plan scope: only MAX rows remain for 'max'.
      await tester.tap(find.byKey(const ValueKey<String>('scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('scope-option-plan')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'max');
      await tester.pumpAndSettle();
      expect(find.text('No students found.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pro');
      await tester.pumpAndSettle();
      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      expect(find.text('Mariam adel samy'), findsNothing);
    });

    testWidgets('subjects tab shows grade subjects',
        (WidgetTester tester) async {
      await _pumpScreen(
        tester,
        subjects: const <SubjectOption>[
          SubjectOption(id: 's1', title: 'Physics', gradeKey: 'grade_one'),
        ],
      );

      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();

      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Ahmed gamal mousa'), findsNothing);
    });

    testWidgets('subject card shows live per-tab lecture counts',
        (WidgetTester tester) async {
      // Regression: published lectures must be reflected on the subject
      // card (same flattened tab lists the details table shows).
      const SubjectLecture published = SubjectLecture(
        id: 'l1',
        title: 'مقطع من اول محاضرة',
        displayOrder: 1,
        status: 'published',
      );
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gradeStudentsProvider('grade_one')
                .overrideWith((ref) => Future.value(_gradeOneData)),
            gradeSubjectsProvider('grade_one').overrideWith(
              (ref) => Stream.value(
                const <SubjectOption>[
                  SubjectOption(
                      id: 's1',
                      title: 'Physics',
                      gradeKey: 'grade_one'),
                ],
              ),
            ),
            tabLecturesProvider((subjectId: 's1', tab: SubjectContentTab.lectures))
                .overrideWith(
                    (ref) => Stream.value(const <SubjectLecture>[published])),
            tabLecturesProvider((subjectId: 's1', tab: SubjectContentTab.revisions))
                .overrideWith((ref) => Stream.value(const <SubjectLecture>[])),
            tabLecturesProvider((subjectId: 's1', tab: SubjectContentTab.finalTab))
                .overrideWith((ref) => Stream.value(const <SubjectLecture>[])),
            tabLecturesProvider((subjectId: 's1', tab: SubjectContentTab.online))
                .overrideWith((ref) => Stream.value(const <SubjectLecture>[])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GradeStudentsScreen(initialGradeKey: 'grade_one'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();

      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Lectures (1)'), findsOneWidget);
      expect(find.text('Revisions (0)'), findsOneWidget);
      expect(find.text('Final (0)'), findsOneWidget);
      expect(find.text('Online (0)'), findsOneWidget);
    });

    testWidgets('grade pills switch grades', (WidgetTester tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('Grade Three').first);
      await tester.pumpAndSettle();

      // Grade three renders its live provider data (2 students).
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Salma mohamed ali'), findsOneWidget);
    });

    testWidgets('view opens student details dialog',
        (WidgetTester tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      expect(find.text('Type: Center'), findsOneWidget);
      expect(
        find.text('Plan: 2 subjects · 1 FREE, 1 PRO'),
        findsOneWidget,
      );
      expect(find.text('Status: Active'), findsOneWidget);
    });

    testWidgets('pending CTA reports the grade',
        (WidgetTester tester) async {
      String? reported;
      await _pumpScreen(
        tester,
        onReviewPending: (String gradeKey) => reported = gradeKey,
      );

      await tester.tap(find.text('Review Pending Requests'));
      await tester.pumpAndSettle();

      expect(reported, 'grade_one');
    });
  });

  group('filterStudents', () {
    const List<GradeStudent> rows = <GradeStudent>[
      GradeStudent(
        id: '1',
        name: 'Ahmed gamal',
        isCenter: true,
        planSummary: StudentPlanSummary(subjects: 2, free: 1, pro: 1),
        isActive: true,
        lastSignIn: '1/1/2026',
      ),
      GradeStudent(
        id: '2',
        name: 'Sara ali',
        isCenter: false,
        planSummary: StudentPlanSummary.empty,
        isActive: false,
        lastSignIn: '2/1/2026',
      ),
    ];

    test('empty query returns everything', () {
      expect(
        filterStudents(rows, StudentSearchScope.name, '  ').length,
        2,
      );
    });

    test('each scope matches its own field', () {
      expect(
        filterStudents(rows, StudentSearchScope.name, 'sara').single.id,
        '2',
      );
      expect(
        filterStudents(rows, StudentSearchScope.type, 'guest').single.id,
        '2',
      );
      expect(
        filterStudents(rows, StudentSearchScope.plan, 'pro').single.id,
        '1',
      );
      expect(
        filterStudents(rows, StudentSearchScope.status, 'inactive')
            .single
            .id,
        '2',
      );
    });

    test('plan scope matches true tier holdings, not a scalar', () {
      // Multi-tier student matches every tier they hold.
      expect(
        filterStudents(rows, StudentSearchScope.plan, 'free').single.id,
        '1',
      );
      expect(
        filterStudents(rows, StudentSearchScope.plan, 'max'),
        isEmpty,
      );
      // Explicit empty state is searchable; stale FREE default is gone.
      expect(
        filterStudents(rows, StudentSearchScope.plan, 'no active')
            .single
            .id,
        '2',
      );
    });
  });

  group('StudentPlanSummary', () {
    test('displayText renders the true distribution', () {
      expect(StudentPlanSummary.empty.displayText, 'No active plan');
      expect(
        const StudentPlanSummary(subjects: 1, pro: 1).displayText,
        '1 subject · 1 PRO',
      );
      // Mirrors the live asmaa mohamed case: MAX + PRO + FREE.
      expect(
        const StudentPlanSummary(subjects: 3, free: 1, pro: 1, max: 1)
            .displayText,
        '3 subjects · 1 FREE, 1 PRO, 1 MAX',
      );
    });

    test('buildStudentPlanSummaries folds rows per student', () {
      final Map<String, StudentPlanSummary> out =
          buildStudentPlanSummaries(
        subscriptions: <({String studentId, String subjectId, String planId})>[
          (studentId: 's1', subjectId: 'sub1', planId: 'p-free'),
          (studentId: 's1', subjectId: 'sub2', planId: 'p-pro'),
          (studentId: 's1', subjectId: 'sub3', planId: 'p-max'),
          (studentId: 's2', subjectId: 'sub1', planId: 'p-gone'),
        ],
        planLabels: <String, String>{
          'p-free': 'FREE',
          'p-pro': 'PRO',
          'p-max': 'MAX',
        },
      );
      expect(out['s1']!.displayText, '3 subjects · 1 FREE, 1 PRO, 1 MAX');
      // Unresolvable plan: subject counted, tier bucket honest.
      expect(out['s2']!.displayText, '1 subject · 1 other');
      expect(out.containsKey('s3'), isFalse);
    });

    test('buildPlanBreakdown shares one subscription axis', () {
      const List<GradeStudent> breakdownRows = <GradeStudent>[
        GradeStudent(
          id: '1',
          name: 'A',
          isCenter: true,
          planSummary: StudentPlanSummary(subjects: 3, free: 1, pro: 1, max: 1),
          isActive: true,
          lastSignIn: '',
        ),
        GradeStudent(
          id: '2',
          name: 'B',
          isCenter: true,
          planSummary: StudentPlanSummary.empty,
          isActive: true,
          lastSignIn: '',
        ),
      ];
      final List<PlanBreakdownRow> breakdown =
          buildPlanBreakdown(breakdownRows);
      // Multi-tier student counted in each tier: shares sum past 100%.
      expect(breakdown[0].label, 'Students with FREE');
      expect(breakdown[0].count, 1);
      expect(breakdown[1].count, 1);
      expect(breakdown[2].count, 1);
      expect(breakdown[3].label, 'No active plan');
      expect(breakdown[3].count, 1);
    });
  });
}
