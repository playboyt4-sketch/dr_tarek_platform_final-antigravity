import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'asmaa mohamed',
  isCenter: true,
  isActive: true,
  lastSignIn: '19/9/2026',
  phone: '01115800180',
);

Future<void> _pumpOverview(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: StudentProfileOverviewScreen(
            student: _student,
            gradeKey: 'grade_one',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the Grade Edit dialog (3rd Edit button: Name / Phone / Grade).
Future<void> _openGradeDialog(WidgetTester tester) async {
  expect(find.text('Edit'), findsNWidgets(4));
  await tester.tap(find.text('Edit').at(2));
  await tester.pumpAndSettle();
  expect(find.text('Grades'), findsOneWidget);
}

void main() {
  group('Student Profile Overview - Grade Edit persistence', () {
    testWidgets('Save with unchanged grade closes without backend call',
        (WidgetTester tester) async {
      await _pumpOverview(tester);
      await _openGradeDialog(tester);
      final int gradeOneBefore =
          find.text('Grade One').evaluate().length;
      final int gradeTwoBefore =
          find.text('Grade Two').evaluate().length;

      // Select the already-active grade, then Save: no-op path pops the
      // dialog without touching any provider (no Firebase in tests).
      await tester.tap(find.text('Grade One').last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Grades'), findsNothing);
      // Displayed grade is unchanged.
      expect(
        find.text('Grade One').evaluate().length,
        gradeOneBefore - 1, // minus the closed dialog option
      );
      expect(
        find.text('Grade Two').evaluate().length,
        gradeTwoBefore - 1, // minus the closed dialog option
      );
    });

    testWidgets('failed write surfaces an error and keeps the old grade',
        (WidgetTester tester) async {
      await _pumpOverview(tester);
      await _openGradeDialog(tester);

      // Pick another grade: the Save path now reaches the
      // `changeStudentGrade` controller. Without a Firebase backend the
      // write fails — the failure must surface via SnackBar instead of
      // silently pretending success, and the dialog must stay open.
      final int gradeOneBefore =
          find.text('Grade One').evaluate().length;
      await tester.tap(find.text('Grade Two').last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Grades'), findsOneWidget);
      expect(
        find.text('تعذّر تنفيذ الإجراء. حاول مرة أخرى.'),
        findsOneWidget,
      );
      // Displayed grade is unchanged (no optimistic local mutation).
      expect(
        find.text('Grade One').evaluate().length,
        gradeOneBefore,
      );
    });
  });
}
