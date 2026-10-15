import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/student_profile_subjects_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/student_profile_overview_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/grade_theme.dart';

const GradeStudent _student = GradeStudent(
  id: 'stu_001',
  name: 'ahmed mohamed gamal',
  isCenter: true,
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

    test('rows keep each subject\'s OWN catalog grade (mixed grades)', () {
      // A grade_three student still holding a grade_two subject: the row
      // grade comes from the subject document, never the student record.
      final rows = buildStudentSubjectRegistrations(
        subjects: const <SubjectOption>[
          SubjectOption(id: 'a', title: 'A', gradeKey: 'grade_two'),
          SubjectOption(id: 'b', title: 'B', gradeKey: 'grade_three'),
        ],
        assignments: const <StudentSubjectAssignment>[
          StudentSubjectAssignment(subjectId: 'a', enabled: true),
          StudentSubjectAssignment(subjectId: 'b', enabled: true),
        ],
        subscriptions: const <StudentSubjectSubscription>[
          StudentSubjectSubscription(subjectId: 'a', planId: 'free'),
          StudentSubjectSubscription(subjectId: 'b', planId: 'pro'),
        ],
        planLabels: const <String, String>{'free': 'FREE', 'pro': 'PRO'},
      );

      expect(rows.map((r) => r.subjectId), <String>['a', 'b']);
      expect(rows.map((r) => r.gradeKey), <String>['grade_two', 'grade_three']);
      expect(GradeTheme.subjectGradeLabel(rows[0].gradeKey), 'Grade Two');
      expect(GradeTheme.subjectGradeLabel(rows[1].gradeKey), 'Grade Three');
    });
  });

  group('GradeTheme.subjectGradeLabel', () {
    test('resolves catalog ids, dashes unknown or missing grades', () {
      expect(GradeTheme.subjectGradeLabel('grade_one'), 'Grade One');
      expect(GradeTheme.subjectGradeLabel('grade_two'), 'Grade Two');
      expect(GradeTheme.subjectGradeLabel('grade_three'), 'Grade Three');
      expect(GradeTheme.subjectGradeLabel('grade_four'), 'Grade Four');
      expect(GradeTheme.subjectGradeLabel(null), '—');
      expect(GradeTheme.subjectGradeLabel(''), '—');
      expect(GradeTheme.subjectGradeLabel('grade_9'), '—');
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

    testWidgets('grade column shows each subject\'s own catalog grade', (
      WidgetTester tester,
    ) async {
      // Grade-three student holding a grade-two subject: the Grade
      // column must follow the SUBJECT, not the student record.
      await _pumpSubjects(
        tester,
        gradeKey: 'grade_three',
        rows: const <StudentSubjectRegistration>[
          StudentSubjectRegistration(
            subjectId: 'sub_old',
            title: 'رياضيات الصف الثاني',
            gradeKey: 'grade_two',
            planLabel: 'FREE',
            enabled: true,
          ),
          StudentSubjectRegistration(
            subjectId: 'sub_new',
            title: 'رياضيات الصف الثالث',
            gradeKey: 'grade_three',
            planLabel: 'PRO',
            enabled: true,
          ),
        ],
      );

      expect(find.text('Grade'), findsOneWidget);
      // 'Grade Two'/'Grade Three' also label the grade-nav pills, so the
      // cell assertions below use findsWidgets; exact per-row mapping is
      // pinned by the buildStudentSubjectRegistrations unit test above.
      expect(find.text('Grade Two'), findsWidgets);
      expect(find.text('Grade Three'), findsWidgets);
      expect(tester.takeException(), isNull);
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

    testWidgets('Save with untouched rows writes nothing (no spurious rows)', (
      WidgetTester tester,
    ) async {
      // Regression guard for the whole-scope commit bug: opening the
      // overlay and saving without toggling anything ON must NOT create
      // disabled assignment rows. Without a Firebase backend in tests a
      // real write would fail — after the fix there is no write at all,
      // so no SnackBar and no summary dialog appear.
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
      // Nothing was toggled ON → no write → no persistence feedback.
      expect(find.byType(SnackBar), findsNothing);
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

    test('untouched rows produce NO write (never default-ON, never OFF rows)', () {
      // No persisted relationship and no explicit touch: nothing enters
      // the commit list. The old whole-scope behavior created disabled
      // assignment rows for these — that is the bug this guards against.
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
      );

      expect(picked, isEmpty);
    });

    test('explicit toggle and plan choices are honored (only the ON row)', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'a': true},
        plans: const <String, String>{'a': 'pro'},
        alreadyRegistered: const <String>{},
      );

      expect(picked.map((p) => p.subjectId), <String>['a']);
      expect(picked.single.enabled, isTrue);
      expect(picked.single.plan, 'pro');
    });

    test('explicit-OFF rows produce NO write', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'a': false, 'b': false},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
      );

      expect(picked, isEmpty);
    });

    test('plans-only entries without a toggle produce NO write', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{},
        plans: const <String, String>{'b': 'max'},
        alreadyRegistered: const <String>{},
      );

      expect(picked, isEmpty);
    });

    test('already-registered subjects are excluded', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'a': true, 'b': true},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{'a'},
      );

      expect(picked.map((p) => p.subjectId), <String>['b']);
    });

    test('stale ON entries outside the scope are still honored', () {
      final picked = buildNewStudentSubjects(
        scope: scope,
        toggles: const <String, bool>{'stale': true},
        plans: const <String, String>{},
        alreadyRegistered: const <String>{},
      );

      expect(picked.map((p) => p.subjectId), <String>['stale']);
    });

    test(
        'Add Other Subject regression: one ON in a multi-grade scope '
        'yields exactly that row (asmaa mohamed incident)', () {
      // Mirrors the incident: Grade One (2 subjects) + Grade Two
      // (3 subjects) displayed, only one toggled ON with FREE.
      // The old code committed all 5 (1 grant + 4 disabled rows).
      const List<SubjectOption> otherScope = <SubjectOption>[
        SubjectOption(
            id: 'fin1', title: 'subject-fin', gradeKey: 'grade_one'),
        SubjectOption(
            id: 'eth1', title: 'subject-eth', gradeKey: 'grade_one'),
        SubjectOption(
            id: 'part2', title: 'subject-part', gradeKey: 'grade_two'),
        SubjectOption(
            id: 'cost2', title: 'subject-cost', gradeKey: 'grade_two'),
        SubjectOption(
            id: 'mid2', title: 'subject-mid', gradeKey: 'grade_two'),
      ];

      final picked = buildNewStudentSubjects(
        scope: otherScope,
        toggles: const <String, bool>{'fin1': true},
        plans: const <String, String>{'fin1': 'free'},
        alreadyRegistered: const <String>{},
      );

      // ONLY the toggled-ON subject results in a write — no sibling rows.
      expect(picked.map((p) => p.subjectId), <String>['fin1']);
      expect(picked.single.enabled, isTrue);
      expect(picked.single.plan, 'free');
    });
  });
}
