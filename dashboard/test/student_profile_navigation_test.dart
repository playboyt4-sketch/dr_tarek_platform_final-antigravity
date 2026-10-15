import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_students_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';

const GradeStudentsData _mockTableData = GradeStudentsData(
  gradeKey: 'grade_one',
  students: <GradeStudent>[
    GradeStudent(
      id: 'stu_001',
      name: 'ahmed mohamed gamal',
      isCenter: true,
      planSummary: StudentPlanSummary(subjects: 1, pro: 1),
      isActive: true,
      lastSignIn: '12/8/2026',
      phone: '01115800180',
    ),
  ],
  pendingCount: 2,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 0, share: 0),
    PlanBreakdownRow(label: 'PRO', count: 1, share: 100),
    PlanBreakdownRow(label: 'MAX', count: 0, share: 0),
    PlanBreakdownRow(label: 'No active plan', count: 0, share: 0),
  ],
  isFallback: false,
);

Future<void> _pumpTable(
  WidgetTester tester, {
  void Function(GradeStudent, String)? onStudentTap,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gradeStudentsProvider('grade_one')
            .overrideWith((ref) => Future.value(_mockTableData)),
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GradeStudentsScreen(
            initialGradeKey: 'grade_one',
            onStudentTap: onStudentTap,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: StudentProfileOverviewScreen(
          student: GradeStudent(
            id: 'stu_001',
            name: 'ahmed mohamed gamal',
            isCenter: true,
            isActive: true,
            lastSignIn: '12/8/2026',
            phone: '01115800180',
          ),
          gradeKey: 'grade_one',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('View → Student Profile Overview navigation', () {
    testWidgets('View calls onStudentTap with the row student (no dialog)',
        (WidgetTester tester) async {
      GradeStudent? tapped;
      String? tappedGrade;
      await _pumpTable(
        tester,
        onStudentTap: (GradeStudent student, String gradeKey) {
          tapped = student;
          tappedGrade = gradeKey;
        },
      );

      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      expect(tapped?.id, 'stu_001');
      expect(tappedGrade, 'grade_one');
      // No legacy dialog is shown when a navigation handler is wired.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('View without handler keeps the legacy dialog',
        (WidgetTester tester) async {
      await _pumpTable(tester);

      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Plan: 1 subject · 1 PRO'), findsOneWidget);
    });

    testWidgets('profile screen binds the passed student',
        (WidgetTester tester) async {
      await _pumpProfile(tester);

      // Sidebar + header per Figma spec.
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Tarek el araby '), findsNothing); // rich-text runs
      // Data rows bound to the student. The phone renders twice by design
      // (hero metadata row + Phone data row, per the Figma frame).
      expect(find.text('01115800180'), findsNWidgets(2));
      expect(find.text('Grade One'), findsWidgets);
      expect(find.text('Center'), findsWidgets);
      // Edit/Done affordances present.
      expect(find.text('Edit'), findsWidgets);
    });

    testWidgets('Name Edit toggles to Done and back',
        (WidgetTester tester) async {
      await _pumpProfile(tester);

      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('Grade Edit opens the 677-wide overlay',
        (WidgetTester tester) async {
      await _pumpProfile(tester);

      // Grade row is the third Edit button (Name, Phone, Grade, type).
      await tester.tap(find.text('Edit').at(2));
      await tester.pumpAndSettle();

      expect(find.text('Grades'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Grades'), findsNothing);
    });

    testWidgets('long hero name scales down without truncation or overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StudentProfileOverviewScreen(
              student: GradeStudent(
                id: 'stu_002',
                name: 'youssef mostafa ibrahim',
                isCenter: false,
                isActive: true,
                lastSignIn: '15/9/2026',
                phone: '01101011588',
              ),
              gradeKey: 'grade_one',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Full name renders (FittedBox scales instead of ellipsizing).
      expect(find.text('youssef mostafa ibrahim'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
