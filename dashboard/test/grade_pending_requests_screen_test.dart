import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/domain/entities/join_application.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_pending_requests_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_pending_requests_screen.dart';

/// Test-only fixtures. These names/phones are synthetic widget-test data
/// and never ship in the production code path: the provider serves only
/// live Firestore rows (empty list when the queue is empty).
List<PendingRequestRow> _rows(String gradeKey) {
  return <PendingRequestRow>[
    PendingRequestRow(
      application: JoinApplication(
        id: 'p1',
        fullName: 'Test Student One',
        phone: '01000000001',
        gradeKey: gradeKey,
        studentType: 'center_student',
        createdAt: DateTime(2026, 9, 3),
      ),
      deviceLabel: 'Test Device A',
      requestDate: '3/9/2026',
    ),
    PendingRequestRow(
      application: JoinApplication(
        id: 'p2',
        fullName: 'Test Student Two',
        phone: '01000000002',
        gradeKey: gradeKey,
        studentType: 'guest',
        createdAt: DateTime(2026, 9, 2),
      ),
      deviceLabel: 'Test Device B',
      requestDate: '2/9/2026',
    ),
  ];
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  String gradeKey = 'grade_one',
  List<PendingRequestRow>? rows,
  Object? rowsError,
  Map<String, List<PendingRequestRow>> rowsByGrade =
      const <String, List<PendingRequestRow>>{},
  List<SubjectOption> subjects = const <SubjectOption>[],
  ValueChanged<String>? onStudentsTab,
  ValueChanged<String>? onSubjectsTab,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Future<List<PendingRequestRow>> valuesFor(String key) {
    if (rowsError != null && key == gradeKey) {
      return Future<List<PendingRequestRow>>.error(rowsError);
    }
    if (key == gradeKey && rows != null) return Future.value(rows);
    return Future.value(
        rowsByGrade[key] ?? (key == gradeKey ? _rows(key) : <PendingRequestRow>[]));
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gradePendingRequestsProvider('grade_one')
            .overrideWith((ref) => valuesFor('grade_one')),
        gradePendingRequestsProvider('grade_two')
            .overrideWith((ref) => valuesFor('grade_two')),
        gradePendingRequestsProvider('grade_three')
            .overrideWith((ref) => valuesFor('grade_three')),
        gradePendingRequestsProvider('grade_four')
            .overrideWith((ref) => valuesFor('grade_four')),
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
    testWidgets('shows an empty state when the queue is empty',
        (WidgetTester tester) async {
      await _pumpScreen(tester, rows: <PendingRequestRow>[]);

      expect(find.text('Pending Requests'), findsOneWidget);
      expect(find.text('No pending requests.'), findsOneWidget);
      expect(find.text('Test Student One'), findsNothing);
      expect(find.text('Test Student Two'), findsNothing);
      expect(find.text('View'), findsNothing);
    });

    testWidgets('shows an error state when Firestore fails, never fake rows',
        (WidgetTester tester) async {
      await _pumpScreen(
        tester,
        rowsError: StateError('unavailable'),
      );

      expect(find.text('Could not load requests.'), findsOneWidget);
      expect(find.text('No pending requests.'), findsNothing);
      expect(find.text('Test Student One'), findsNothing);
      expect(find.text('Test Student Two'), findsNothing);
    });

    testWidgets('renders banner, headers and live rows',
        (WidgetTester tester) async {
      await _pumpScreen(tester, rows: _rows('grade_one'));

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
      expect(find.text('Test Student One'), findsOneWidget);
      expect(find.text('01000000001'), findsOneWidget);
      expect(find.text('Test Device A'), findsOneWidget);
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

      expect(find.text('Test Student One'), findsOneWidget);
      expect(find.text('Test Student Two'), findsOneWidget);
      expect(find.text('Test Device B'), findsOneWidget);
      expect(find.text('2/9/2026'), findsOneWidget);
    });

    testWidgets('grade pills switch the queue; empty stays empty',
        (WidgetTester tester) async {
      await _pumpScreen(
        tester,
        rows: _rows('grade_one'),
        rowsByGrade: const <String, List<PendingRequestRow>>{
          'grade_two': <PendingRequestRow>[],
        },
      );

      await tester.tap(find.text('Grade Two').first);
      await tester.pumpAndSettle();

      // Grade two has no real requests: empty state, accent switches,
      // and no rows leak across grades.
      expect(find.text('No pending requests.'), findsOneWidget);
      expect(find.text('Test Student One'), findsNothing);
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
}
