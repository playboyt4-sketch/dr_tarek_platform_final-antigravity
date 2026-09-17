import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
  plan: 'PRO',
  isActive: true,
  lastSignIn: '12/8/2026',
  phone: '01115800180',
);

const List<StudentSubjectRegistration> _rows = <StudentSubjectRegistration>[
  StudentSubjectRegistration(
    subjectId: 'sub_fin',
    title: 'محاسبة مالية',
    gradeKey: 'grade_one',
    planLabel: 'PRO',
    enabled: true,
  ),
  StudentSubjectRegistration(
    subjectId: 'sub_tax',
    title: 'محاسبة ضريبية',
    gradeKey: 'grade_one',
    planLabel: 'FREE',
    enabled: false,
  ),
];

ProviderScope _membershipsScope({
  required Widget child,
  List<StudentSubjectRegistration>? rows,
}) {
  return ProviderScope(
    overrides: [
      studentProfileSubjectsProvider('stu_001').overrideWith(
        (ref) => Stream.value(rows ?? _rows),
      ),
    ],
    child: child,
  );
}

Future<void> _pumpMemberships(
  WidgetTester tester, {
  List<StudentSubjectRegistration>? rows,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _membershipsScope(
      rows: rows,
      child: const MaterialApp(
        home: Scaffold(
          body: StudentProfileOverviewScreen(
            student: _student,
            gradeKey: 'grade_one',
            initialNav: 'Memberships',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Student Profile → Memberships tab', () {
    testWidgets('persistent header stays mounted with Memberships active',
        (WidgetTester tester) async {
      await _pumpMemberships(tester);

      // Top half intact: brand, grade nav, category, hero, sub-nav.
      expect(find.text('Tarek el araby Platform'), findsOneWidget);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('ahmed mohamed gamal'), findsWidgets);
      expect(find.text('Memberships'), findsOneWidget);

      // Body: type pill + memberships table (no overview rows).
      expect(find.text('Student Type'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Name'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('table shows status badges and change-plan actions',
        (WidgetTester tester) async {
      await _pumpMemberships(tester);

      expect(find.text('01.'), findsOneWidget);
      expect(find.text('02.'), findsOneWidget);
      expect(find.text('محاسبة مالية'), findsOneWidget);
      expect(find.text('PRO'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Change Plan'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Student Type pill opens the type overlay and saves',
        (WidgetTester tester) async {
      await _pumpMemberships(tester);

      await tester.tap(find.text('Student Type'));
      await tester.pumpAndSettle();

      expect(find.text('Center'), findsOneWidget);
      expect(find.text('Guest'), findsWidgets);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Overlay closes; pill persists.
      expect(find.text('Save'), findsNothing);
      expect(find.text('Student Type'), findsOneWidget);
    });

    testWidgets('Change Plan opens the plan overlay with current preselected',
        (WidgetTester tester) async {
      await _pumpMemberships(tester);

      await tester.tap(find.text('Change Plan').first);
      await tester.pumpAndSettle();

      expect(find.text('Student Plan'), findsOneWidget);
      // FREE also renders in the table row behind the dialog.
      expect(find.text('FREE'), findsWidgets);
      expect(find.text('PRO'), findsWidgets);
      expect(find.text('MAX'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Switching selection then saving attempts the backend call; with
      // no backend in tests the failure surfaces via SnackBar.
      await tester.tap(find.text('MAX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('sub-nav switches Memberships back to Overview',
        (WidgetTester tester) async {
      await _pumpMemberships(tester);

      expect(find.text('Status'), findsOneWidget);

      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      expect(find.text('Status'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
    });
  });
}
