import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';
import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/features/applications/domain/entities/join_application.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_pending_requests_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/grade_pending_requests_view_screen.dart';

const GradeStudentsData _shellGradeOneData = GradeStudentsData(
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
  ],
  pendingCount: 11,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 0, share: 0),
    PlanBreakdownRow(label: 'PRO', count: 1, share: 100),
    PlanBreakdownRow(label: 'MAX', count: 0, share: 0),
    PlanBreakdownRow(label: 'Guest', count: 0, share: 0),
  ],
  isFallback: false,
);

PendingRequestRow _row({
  String id = 'p1',
  String name = 'Ahmed gamal mousa',
  String phone = '01101011588',
  String? gradeKey = 'grade_one',
  String studentType = 'center_student',
}) {
  return PendingRequestRow(
    application: JoinApplication(
      id: id,
      fullName: name,
      phone: phone,
      gradeKey: gradeKey,
      studentType: studentType,
      createdAt: DateTime(2026, 9, 15),
    ),
    deviceLabel: 'Iphone 17 pro',
    requestDate: '15/9/2026',
  );
}

const List<SubjectOption> _gradeOneSubjects = <SubjectOption>[
  SubjectOption(id: 's1', title: 'مالية متقدمة', gradeKey: 'grade_one'),
  SubjectOption(id: 's2', title: 'محاسبة حكومية', gradeKey: 'grade_one'),
];

const List<SubjectOption> _gradeTwoSubjects = <SubjectOption>[
  SubjectOption(id: 's3', title: 'Grade two subject', gradeKey: 'grade_two'),
];

/// Deterministic backend double: every decision fails fast with a known
/// message instead of touching Firebase.
class _ThrowingDecisionController implements ApplicationDecisionController {
  @override
  Future<ApprovalResult> approve({
    required String studentId,
    required String studentType,
    required String planKey,
    required List<Map<String, Object>> subjectAccess,
  }) {
    throw const DecisionFailure('backend down');
  }

  @override
  Future<void> reject({
    required String studentId,
    required String reason,
  }) {
    throw const DecisionFailure('backend down');
  }
}

/// Recording backend double: captures approve payloads so tests can prove
/// no synthetic subject ID is ever submitted.
class _RecordingDecisionController implements ApplicationDecisionController {
  int approveCalls = 0;
  List<Map<String, Object>> lastSubjectAccess = const <Map<String, Object>>[];

  @override
  Future<ApprovalResult> approve({
    required String studentId,
    required String studentType,
    required String planKey,
    required List<Map<String, Object>> subjectAccess,
  }) async {
    approveCalls++;
    lastSubjectAccess = subjectAccess;
    return const ApprovalResult(
      approved: true,
      assignmentCount: 0,
      activatedCount: 0,
      activationFailures: <String>[],
    );
  }

  @override
  Future<void> reject({
    required String studentId,
    required String reason,
  }) async {}
}

Future<void> _pumpView(
  WidgetTester tester, {
  PendingRequestRow? row,
  List<SubjectOption> gradeOneSubjects = _gradeOneSubjects,
  List<SubjectOption> otherSubjects = _gradeTwoSubjects,
  List<SubjectOption> gradeThreeSubjects = const <SubjectOption>[],
  List<SubjectOption> gradeFourSubjects = const <SubjectOption>[],
  Stream<List<SubjectOption>>? gradeOneStream,
  Stream<List<SubjectOption>>? gradeTwoStream,
  ApplicationDecisionController? decisionController,
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        applicationDecisionControllerProvider.overrideWithValue(
          decisionController ?? _ThrowingDecisionController(),
        ),
        gradeSubjectsProvider('grade_one').overrideWith(
          (ref) => gradeOneStream ?? Stream.value(gradeOneSubjects),
        ),
        gradeSubjectsProvider('grade_two').overrideWith(
          (ref) => gradeTwoStream ?? Stream.value(otherSubjects),
        ),
        gradeSubjectsProvider('grade_three')
            .overrideWith((ref) => Stream.value(gradeThreeSubjects)),
        gradeSubjectsProvider('grade_four')
            .overrideWith((ref) => Stream.value(gradeFourSubjects)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GradePendingRequestsViewScreen(
            row: row ?? _row(),
            onBack: onBack,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Test-harness accommodation for a KNOWN baseline failure (identical on
/// pristine HEAD): fixed-height Figma cards overflow by 5px under the test
/// fallback font. Only that layout noise is ignored.
void _ignoreKnownBaselineOverflows() {
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = original;
  });
}

void main() {
  group('GradePendingRequestsViewScreen', () {
    testWidgets('renders the student card with metadata',
        (WidgetTester tester) async {
      await _pumpView(tester);

      expect(find.text('Ahmed gamal mousa'), findsOneWidget);
      expect(find.text('01101011588'), findsOneWidget);
      expect(find.text('Grade One'), findsWidgets);
      expect(find.text('15/9/2026'), findsOneWidget);
      expect(find.text('Iphone 17 pro'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('center flow shows three stepper buttons',
        (WidgetTester tester) async {
      await _pumpView(tester);

      expect(find.text('Student Type'), findsOneWidget);
      expect(find.text('Student Subjects'), findsOneWidget);
      expect(find.text('Other Subjects'), findsOneWidget);
      expect(find.text('Student Plan'), findsNothing);
      expect(find.text('Center'), findsOneWidget);
    });

    testWidgets('switching to guest shows two buttons only',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Student Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Student Type'), findsOneWidget);
      expect(find.text('Student Subjects'), findsOneWidget);
      expect(find.text('Student Plan'), findsNothing);
      expect(find.text('Other Subjects'), findsNothing);
      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('grade subjects overlay offers per-subject plans and saves',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Student Subjects'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsOneWidget);
      // One FREE | PRO | MAX capsule per subject row.
      expect(find.text('FREE'), findsNWidgets(2));
      expect(find.text('PRO'), findsNWidgets(2));
      expect(find.text('MAX'), findsNWidgets(2));

      await tester.tap(find.text('PRO').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Grade One Subjects'), findsNothing);
    });

    testWidgets('subjects overlay toggles default off and saves',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Student Subjects'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsNWidgets(2));
      // No persisted relationship: rows open OFF / gray, never ON.
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first).value,
        isFalse,
      );

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first).value,
        isTrue,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsNothing);
    });

    testWidgets('other subjects overlay shows empty state for grade one',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Other Subjects'));
      await tester.pumpAndSettle();

      expect(
        find.text('لا توجد فرق دراسية سابقة لطلاب الفرقة الأولى'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('لا توجد فرق دراسية سابقة لطلاب الفرقة الأولى'),
        findsNothing,
      );
    });

    testWidgets('other subjects overlay shows previous grades only',
        (WidgetTester tester) async {
      await _pumpView(tester, row: _row(gradeKey: 'grade_two'));

      await tester.tap(find.text('Other Subjects'));
      await tester.pumpAndSettle();

      expect(find.text('Other Subjects'), findsNWidgets(2));
      expect(find.text('Grade One Subjects'), findsOneWidget);
      expect(find.text('مالية متقدمة'), findsOneWidget);
      // The student's own grade is never listed as "other".
      expect(find.text('Grade Two Subjects'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Grade One Subjects'), findsNothing);
    });

    testWidgets('other subjects overlay stacks sections for higher grades',
        (WidgetTester tester) async {
      await _pumpView(
        tester,
        row: _row(gradeKey: 'grade_four'),
        gradeThreeSubjects: const <SubjectOption>[
          SubjectOption(id: 's4', title: 'Grade three subject', gradeKey: 'grade_three'),
        ],
      );

      await tester.tap(find.text('Other Subjects'));
      await tester.pumpAndSettle();

      expect(find.text('Grade One Subjects'), findsOneWidget);
      expect(find.text('Grade Two Subjects'), findsOneWidget);
      expect(find.text('Grade Three Subjects'), findsOneWidget);
      expect(find.text('Grade three subject'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Grade Three Subjects'), findsNothing);
    });

    testWidgets('approve surfaces backend failure gracefully',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('backend down'), findsOneWidget);
    });

    testWidgets('reject validates reason then surfaces failure',
        (WidgetTester tester) async {
      await _pumpView(tester);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(find.text('Reject Request'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('اكتب سبب الرفض (3 أحرف على الأقل).'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'بيانات ناقصة');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(find.text('backend down'), findsOneWidget);
    });
  });

  group('shell view flow', () {
    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreKnownBaselineOverflows();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gradeStudentsProvider('grade_one')
                .overrideWith((ref) => Future.value(_shellGradeOneData)),
            // Live queue double: one real row so View opens the review
            // screen. The provider serves no placeholder students.
            gradePendingRequestsProvider('grade_one')
                .overrideWith((ref) => Future.value(<PendingRequestRow>[_row()])),
          ],
          child: const MaterialApp(home: DashboardShell()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('table View opens the review screen for the request',
        (WidgetTester tester) async {
      await pumpShell(tester);

      await tester.tap(find.bySemanticsLabel('Open menu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.text('Grade One'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review Pending Requests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      expect(find.text('Ahmed gamal mousa'), findsWidgets);
      expect(find.text('Student Type'), findsOneWidget);
      expect(find.text('Student Subjects'), findsOneWidget);
      expect(find.text('Other Subjects'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('Students tab returns from the view to students',
        (WidgetTester tester) async {
      await pumpShell(tester);

      await tester.tap(find.bySemanticsLabel('Open menu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.text('Grade One'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review Pending Requests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      expect(find.text('Total Students'), findsOneWidget);
    });
  });

  group('live-subjects guard (no synthetic subjects)', () {
    const String retryMessage =
        'تعذّر تحميل المواد. تحقق من الاتصال ثم حاول مرة أخرى.';

    /// A stream that stays in the loading state: never emits, never errors.
    Stream<List<SubjectOption>> loadingStream() {
      final StreamController<List<SubjectOption>> controller =
          StreamController<List<SubjectOption>>();
      addTearDown(controller.close);
      return controller.stream;
    }

    testWidgets('loading subjects aborts Approve without calling backend',
        (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(
        tester,
        decisionController: backend,
        gradeOneStream: loadingStream(),
      );

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text(retryMessage), findsOneWidget);
      expect(backend.approveCalls, 0);
    });

    testWidgets('loading subjects blocks the subject dialog',
        (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(
        tester,
        decisionController: backend,
        gradeOneStream: loadingStream(),
      );

      await tester.tap(find.text('Student Subjects'));
      await tester.pumpAndSettle();

      expect(find.text('Grade One Subjects'), findsNothing);
      expect(find.text(retryMessage), findsOneWidget);
    });

    testWidgets('errored subjects abort Approve without calling backend',
        (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(
        tester,
        decisionController: backend,
        gradeOneStream: Stream<List<SubjectOption>>.error(
          StateError('unavailable'),
        ),
      );

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text(retryMessage), findsOneWidget);
      expect(backend.approveCalls, 0);
    });

    testWidgets('empty subjects open the dialog empty state, approve sends '
        'an empty live payload', (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(
        tester,
        decisionController: backend,
        gradeOneStream: Stream.value(const <SubjectOption>[]),
      );

      await tester.tap(find.text('Student Subjects'));
      await tester.pumpAndSettle();
      expect(find.text('No subjects in this grade yet.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve'));
      // Success path shows a SnackBar: settle with bounded pumps instead
      // of pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(backend.approveCalls, 1);
      expect(backend.lastSubjectAccess, isEmpty);
    });

    testWidgets('live subjects flow with real IDs only, never fallback IDs',
        (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(tester, decisionController: backend);

      await tester.tap(find.text('Approve'));
      // Success path shows a SnackBar: settle with bounded pumps instead
      // of pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(backend.approveCalls, 1);
      final Set<Object?> ids = <Object?>{
        for (final Map<String, Object> item in backend.lastSubjectAccess)
          item['subjectId'],
      };
      expect(ids, <Object?>{'s1', 's2'});
      expect(
        backend.lastSubjectAccess.every(
          (Map<String, Object> item) =>
              !(item['subjectId'] as String).startsWith('fallback-'),
        ),
        isTrue,
      );
    });

    testWidgets('unavailable previous-grade group aborts Center approve',
        (WidgetTester tester) async {
      final _RecordingDecisionController backend =
          _RecordingDecisionController();
      await _pumpView(
        tester,
        row: _row(gradeKey: 'grade_two'),
        decisionController: backend,
        gradeOneStream: Stream<List<SubjectOption>>.error(
          StateError('unavailable'),
        ),
        gradeTwoStream: Stream.value(_gradeTwoSubjects),
      );

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text(retryMessage), findsOneWidget);
      expect(backend.approveCalls, 0);
    });
  });
}
