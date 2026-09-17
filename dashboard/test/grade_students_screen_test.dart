import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_students_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/scoped_search_bar.dart';

const GradeStudentsData _gradeOneData = GradeStudentsData(
  gradeKey: 'grade_one',
  students: <GradeStudent>[
    GradeStudent(
      id: 'a1',
      name: 'Ahmed gamal mousa',
      isCenter: true,
      plan: 'PRO',
      isActive: true,
      lastSignIn: '12/8/2026',
    ),
    GradeStudent(
      id: 'a2',
      name: 'Mariam adel samy',
      isCenter: true,
      plan: 'FREE',
      isActive: true,
      lastSignIn: '11/8/2026',
    ),
    GradeStudent(
      id: 'a3',
      name: 'Omar khaled hassan',
      isCenter: false,
      plan: 'FREE',
      isActive: false,
      lastSignIn: '9/8/2026',
    ),
  ],
  pendingCount: 11,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 198, share: 44),
    PlanBreakdownRow(label: 'PRO', count: 153, share: 34),
    PlanBreakdownRow(label: 'MAX', count: 45, share: 10),
    PlanBreakdownRow(label: 'Guest', count: 54, share: 12),
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
      plan: 'MAX',
      isActive: true,
      lastSignIn: '10/8/2026',
    ),
    GradeStudent(
      id: 'b2',
      name: 'Nour eldin sami',
      isCenter: false,
      plan: 'FREE',
      isActive: true,
      lastSignIn: '9/8/2026',
    ),
  ],
  pendingCount: 5,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 0, share: 0),
    PlanBreakdownRow(label: 'PRO', count: 0, share: 0),
    PlanBreakdownRow(label: 'MAX', count: 1, share: 50),
    PlanBreakdownRow(label: 'Guest', count: 1, share: 50),
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
      expect(find.text('Free: 198 (44%)'), findsOneWidget);
      expect(find.text('PRO: 153 (34%)'), findsOneWidget);
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
      expect(find.text('Plan: PRO'), findsOneWidget);
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
        plan: 'PRO',
        isActive: true,
        lastSignIn: '1/1/2026',
      ),
      GradeStudent(
        id: '2',
        name: 'Sara ali',
        isCenter: false,
        plan: 'FREE',
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
  });
}
