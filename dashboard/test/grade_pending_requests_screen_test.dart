import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/domain/entities/join_application.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_pending_requests_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_pending_requests_screen.dart';

List<PendingRequestRow> _rows(String gradeKey) {
  return <PendingRequestRow>[
    PendingRequestRow(
      application: JoinApplication(
        id: 'p1',
        fullName: 'Ahmed gamal mousa',
        phone: '01101011588',
        gradeKey: gradeKey,
        studentType: 'center_student',
        createdAt: DateTime(2026, 9, 3),
      ),
      deviceLabel: 'I phone 15 pro',
      requestDate: '3/9/2026',
    ),
    PendingRequestRow(
      application: JoinApplication(
        id: 'p2',
        fullName: 'Mariam adel samy',
        phone: '01022334455',
        gradeKey: gradeKey,
        studentType: 'guest',
        createdAt: DateTime(2026, 9, 2),
      ),
      deviceLabel: 'Samsung A54',
      requestDate: '2/9/2026',
    ),
  ];
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  String gradeKey = 'grade_one',
  List<PendingRequestRow>? rows,
  List<SubjectOption> subjects = const <SubjectOption>[],
  ValueChanged<String>? onStudentsTab,
  ValueChanged<String>? onSubjectsTab,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (rows != null)
          gradePendingRequestsProvider(gradeKey)
              .overrideWith((ref) => Future.value(rows)),
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_two')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_three')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider('grade_four')
            .overrideWith((ref) => Stream.value(subjects)),
        gradeSubjectsProvider(null)
            .overrideWith((ref) => Stream.value(subjects)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GradePendingRequestsScreen(
            initialGradeKey: gradeKey,
            onStudentsTab: onStudentsTab,
            onSubjectsTab: onSubjectsTab,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GradePendingRequestsScreen', () {
    testWidgets('renders banner, headers and Figma fallback rows',
        (WidgetTester tester) async {
      // No provider override: Firestore is unreachable in tests, so the
      // Figma fallback fills the table.
      await _pumpScreen(tester);

      expect(find.text('Pending Requests'), findsOneWidget);
      for (final String header in <String>[
        'No.',
        'Student Name',
        'Phone Number',
        'Device',
        'Request date',
        'Action',
      ]) {
        expect(find.text(header), findsOneWidget);
      }
      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      expect(find.text('01101011588'), findsOneWidget);
      expect(find.text('I phone 15 pro'), findsWidgets);
      expect(find.text('3/9/2026'), findsOneWidget);
      expect(find.text('01.'), findsOneWidget);
      expect(find.text('View'), findsWidgets);
      expect(find.text('Grade One'), findsWidgets);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Subjects'), findsOneWidget);
    });

    testWidgets('renders live provider rows with device + date',
        (WidgetTester tester) async {
      await _pumpScreen(tester, rows: _rows('grade_one'));

      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      expect(find.text('Mariam adel samy'), findsOneWidget);
      expect(find.text('Samsung A54'), findsOneWidget);
      expect(find.text('2/9/2026'), findsOneWidget);
    });

    testWidgets('grade pills switch the queue', (WidgetTester tester) async {
      await _pumpScreen(tester, rows: _rows('grade_one'));

      await tester.tap(find.text('Grade Two').first);
      await tester.pumpAndSettle();

      // Grade two falls back (no override): still full, accent switches.
      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      expect(find.text('Pending Requests'), findsOneWidget);
    });

    testWidgets('tabs report navigation', (WidgetTester tester) async {
      String? studentsGrade;
      String? subjectsGrade;
      await _pumpScreen(
        tester,
        rows: _rows('grade_one'),
        onStudentsTab: (String gradeKey) => studentsGrade = gradeKey,
        onSubjectsTab: (String gradeKey) => subjectsGrade = gradeKey,
      );

      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();
      expect(studentsGrade, 'grade_one');

      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();
      expect(subjectsGrade, 'grade_one');
    });

    testWidgets('view opens the decision dialog',
        (WidgetTester tester) async {
      await _pumpScreen(tester, rows: _rows('grade_one'));

      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      expect(find.text('قبول الطلب'), findsOneWidget);
      expect(find.text('رفض الطلب'), findsOneWidget);
      expect(find.text('تأكيد القبول'), findsOneWidget);
    });
  });

  group('formatRequestDate', () {
    test('formats D/M/YYYY and dashes nulls', () {
      expect(formatRequestDate(DateTime(2026, 9, 3)), '3/9/2026');
      expect(formatRequestDate(null), '—');
    });
  });

  group('fallbackPendingRequests', () {
    test('matches the Figma reference row first', () {
      final List<PendingRequestRow> rows =
          fallbackPendingRequests('grade_one');

      expect(rows, isNotEmpty);
      expect(rows.first.application.fullName, 'Ahmed gamal mousa');
      expect(rows.first.application.phone, '01101011588');
      expect(rows.first.deviceLabel, 'I phone 15 pro');
      expect(rows.first.requestDate, '3/9/2026');
      expect(rows.first.application.gradeKey, 'grade_one');
    });
  });
}
