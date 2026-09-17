import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
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

ProviderScope _subjectsScope({
  required Widget child,
  List<StudentSubjectRegistration>? rows,
  Map<String, List<SubjectOption>>? gradeSubjects,
}) {
  List<SubjectOption> subjectsFor(String key) =>
      gradeSubjects?[key] ?? const <SubjectOption>[];
  return ProviderScope(
    overrides: [
      studentProfileSubjectsProvider('stu_001').overrideWith(
        (ref) => Stream.value(rows ?? _rows),
      ),
      for (final String key in <String>[
        'grade_one',
        'grade_two',
        'grade_three',
        'grade_four',
      ])
        gradeSubjectsProvider(key).overrideWith(
          (ref) => Stream.value(subjectsFor(key)),
        ),
    ],
    child: child,
  );
}

Future<void> _pumpSubjects(
  WidgetTester tester, {
  String gradeKey = 'grade_one',
  List<StudentSubjectRegistration>? rows,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _subjectsScope(
      rows: rows,
      child: MaterialApp(
        home: Scaffold(
          body: StudentProfileOverviewScreen(
            student: _student,
            gradeKey: gradeKey,
            initialNav: 'Subjects',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('buildStudentSubjectRegistrations', () {
    test('lists only registered subjects with per-subject plans', () {
      final rows = buildStudentSubjectRegistrations(
        subjects: const <SubjectOption>[
          SubjectOption(id: 'a', title: 'A', gradeKey: 'grade_one'),
          SubjectOption(id: 'b', title: 'B', gradeKey: 'grade_one'),
          SubjectOption(id: 'c', title: 'C', gradeKey: 'grade_one'),
        ],
        assignments: const <StudentSubjectAssignment>[
          StudentSubjectAssignment(subjectId: 'a', enabled: true),
          StudentSubjectAssignment(subjectId: 'b', enabled: false),
        ],
        subscriptions: const <StudentSubjectSubscription>[
          StudentSubjectSubscription(subjectId: 'a', planId: 'pro'),
          StudentSubjectSubscription(subjectId: 'b', planId: 'free'),
        ],
        planLabels: const <String, String>{'pro': 'PRO', 'free': 'FREE'},
      );

      // `c` was never registered: it must not appear.
      expect(rows.map((r) => r.subjectId), <String>['a', 'b']);
      // Plan is subject-scoped, not a global student plan.
      expect(rows[0].planLabel, 'PRO');
      expect(rows[1].planLabel, 'FREE');
      expect(rows[0].enabled, isTrue);
      expect(rows[1].enabled, isFalse);
    });

    test('missing subscription renders empty plan (never invented)', () {
      final rows = buildStudentSubjectRegistrations(
        subjects: const <SubjectOption>[
          SubjectOption(id: 'a', title: 'A', gradeKey: 'grade_one'),
        ],
        assignments: const <StudentSubjectAssignment>[
          StudentSubjectAssignment(subjectId: 'a', enabled: true),
        ],
        subscriptions: const <StudentSubjectSubscription>[],
        planLabels: const <String, String>{},
      );

      expect(rows, hasLength(1));
      expect(rows.single.planLabel, isEmpty);
    });

    test('assignments without a catalog subject are skipped', () {
      final rows = buildStudentSubjectRegistrations(
        subjects: const <SubjectOption>[],
        assignments: const <StudentSubjectAssignment>[
          StudentSubjectAssignment(subjectId: 'ghost', enabled: true),
        ],
        subscriptions: const <StudentSubjectSubscription>[],
        planLabels: const <String, String>{},
      );

      expect(rows, isEmpty);
    });
  });

  group('planDisplayForKey', () {
    test('maps canonical plan keys to display labels', () {
      expect(planDisplayForKey('center_pro'), 'PRO');
      expect(planDisplayForKey('center_max'), 'MAX');
      expect(planDisplayForKey('center_free'), 'FREE');
      expect(planDisplayForKey('public_free'), 'FREE');
      expect(planDisplayForKey('guest'), 'FREE');
      expect(planDisplayForKey(null), isEmpty);
      expect(planDisplayForKey('unknown'), isEmpty);
    });
  });

  group('Student Profile → Subjects tab', () {
    testWidgets('grade one shows table + single Add Subject', (
      WidgetTester tester,
    ) async {
      await _pumpSubjects(tester);

      // Table header, exactly the specified columns (the persistent
      // header carries two more 'Subjects' labels: the category
      // switcher tab and the active sub-nav pill).
      expect(find.text('No.'), findsOneWidget);
      expect(find.text('Subjects'), findsNWidgets(3));
      expect(find.text('plan'), findsOneWidget);
      expect(find.text('Access'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);

      // Registered rows with subject-scoped plans.
      expect(find.text('محاسبة مالية'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      // Presentation-only numbering.
      expect(find.text('01.'), findsOneWidget);
      expect(find.text('02.'), findsOneWidget);

      // Row actions.
      expect(find.text('Delete'), findsNWidgets(2));

      // Grade One: only Add Subject.
      expect(find.text('Add Subject'), findsOneWidget);
      expect(find.text('Add Other Subject'), findsNothing);

      // Subjects pill is the active one; shell stays intact.
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('grade four shows Add Subject + Add Other Subject', (
      WidgetTester tester,
    ) async {
      await _pumpSubjects(tester, gradeKey: 'grade_four');

      expect(find.text('Add Subject'), findsOneWidget);
      expect(find.text('Add Other Subject'), findsOneWidget);
    });

    testWidgets('empty registrations keep add actions available', (
      WidgetTester tester,
    ) async {
      await _pumpSubjects(
        tester,
        rows: const <StudentSubjectRegistration>[],
      );

      expect(find.text('Delete'), findsNothing);
      expect(find.text('Add Subject'), findsOneWidget);
    });

    testWidgets('sidebar Subjects pill switches from Overview', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _subjectsScope(
          child: const MaterialApp(
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

      // Overview content first, no subjects table.
      expect(find.text('No.'), findsNothing);

      // The sidebar pill is the first 'Subjects' in the tree (the
      // Students/Subjects sub-tabs render after the sidebar).
      await tester.tap(find.text('Subjects').first);
      await tester.pumpAndSettle();

      expect(find.text('No.'), findsOneWidget);
      expect(find.text('محاسبة مالية'), findsOneWidget);
    });

    testWidgets('Delete opens confirmation; Cancel keeps the row', (
      WidgetTester tester,
    ) async {
      await _pumpSubjects(tester);

      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();

      expect(find.text('Remove Subject'), findsOneWidget);
      expect(
        find.textContaining('from this student\'s profile'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Subject'), findsNothing);
      // Nothing was removed: both rows still render.
      expect(find.text('محاسبة مالية'), findsOneWidget);
      expect(find.text('محاسبة ضريبية'), findsOneWidget);
    });

    testWidgets('Save with untouched rows reaches persistence (no silent drop)', (
      WidgetTester tester,
    ) async {
      // Full wiring check: overlay Save must invoke the commit path even
      // when the user touches nothing (rows resolve OFF, still committed).
      // Without a Firebase backend in tests the write fails — the failure
      // must surface via SnackBar instead of vanishing silently.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _subjectsScope(
          rows: const <StudentSubjectRegistration>[],
          gradeSubjects: const <String, List<SubjectOption>>{
            'grade_one': <SubjectOption>[
              SubjectOption(
                id: 'sub_new',
                title: 'محاسبة إدارية',
                gradeKey: 'grade_one',
              ),
            ],
          },
          child: const MaterialApp(
            home: Scaffold(
              body: StudentProfileOverviewScreen(
                student: _student,
                gradeKey: 'grade_one',
                initialNav: 'Subjects',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Subject'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsOneWidget);
      // Unassigned subject opens OFF / gray.
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first).value,
        isFalse,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Grade One Subjects'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('reopened overlay reflects persisted toggles', (
      WidgetTester tester,
    ) async {
      // Persisted ON stays ON; unassigned subjects open OFF — for test
      // students (no assignments) every toggle opens OFF / gray.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _subjectsScope(
          rows: const <StudentSubjectRegistration>[
            StudentSubjectRegistration(
              subjectId: 'sub_fin',
              title: 'محاسبة مالية',
              gradeKey: 'grade_one',
              planLabel: 'PRO',
              enabled: true,
            ),
          ],
          gradeSubjects: const <String, List<SubjectOption>>{
            'grade_one': <SubjectOption>[
              SubjectOption(
                id: 'sub_fin',
                title: 'محاسبة مالية',
                gradeKey: 'grade_one',
              ),
              SubjectOption(
                id: 'sub_new',
                title: 'محاسبة إدارية',
                gradeKey: 'grade_one',
              ),
            ],
          },
          child: const MaterialApp(
            home: Scaffold(
              body: StudentProfileOverviewScreen(
                student: _student,
                gradeKey: 'grade_one',
                initialNav: 'Subjects',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Subject'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsOneWidget);

      expect(find.byType(CupertinoSwitch), findsNWidgets(2));
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).at(0)).value,
        isTrue,
      );
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).at(1)).value,
        isFalse,
      );
    });
  });

  group('buildNewStudentSubjects (add-flow picks)', () {
    const List<SubjectOption> scope = <SubjectOption>[
      SubjectOption(id: 'a', title: 'A', gradeKey: 'grade_one'),
      SubjectOption(id: 'b', title: 'B', gradeKey: 'grade_one'),
    ];

    test('untouched rows resolve to OFF, never default-ON', () {
      // No persisted relationship and no explicit touch: every row
      // resolves OFF (test/design students therefore open all-OFF).
      // Rows are still committed with their displayed OFF state —
      // nothing is silently dropped.
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
      );

      expect(picked.map((p) => p.subjectId), <String>['a', 'b']);
      expect(picked.every((p) => !p.enabled), isTrue);
      expect(picked.every((p) => p.plan == 'free'), isTrue);
    });

    test('explicit toggle and plan choices are honored', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'a': true},
        plans: const <String, String>{'a': 'pro'},
        alreadyRegistered: const <String>{},
      );

      expect(picked, hasLength(2));
      expect(picked[0].enabled, isTrue);
      expect(picked[0].plan, 'pro');
      expect(picked[1].enabled, isFalse);
      expect(picked[1].plan, 'free');
    });

    test('already-registered subjects are excluded', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{'a'},
      );

      expect(picked.map((p) => p.subjectId), <String>['b']);
    });

    test('stale map entries outside the scope are still honored', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'stale': true},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
      );

      expect(picked.map((p) => p.subjectId), <String>['a', 'b', 'stale']);
    });
  });
}
