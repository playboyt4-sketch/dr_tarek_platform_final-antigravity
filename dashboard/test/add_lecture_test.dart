import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/subject_details_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/screens/subject_details_screen.dart';
import 'package:drtarek_dashboard/features/students/presentation/widgets/add_lecture_overlay.dart';

/// Fake for [SubjectDetailsController]: records creation payloads and
/// replays success/failure without Firestore. The whole suite runs with
/// no Firebase app initialized, so any direct Firestore/Firebase call
/// from presentation would throw — passing proves test 17.
class FakeLectureController implements SubjectDetailsController {
  int nextOrderResult = 4;
  final List<Map<String, Object?>> created = <Map<String, Object?>>[];
  bool failCreate = false;

  @override
  Future<void> deleteLecture(String lectureId) async {}

  @override
  Future<void> deleteSubject(String subjectId) async {}

  @override
  Future<String> createLectureFull({
    required String subjectId,
    required SubjectContentTab tab,
    required String title,
    required int displayOrder,
    DateTime? publishDateTime,
    required bool publishNow,
    required bool guestEnabled,
    int? previewMinutes,
    required List<NewLectureResource> resources,
    required Map<String, bool> accessByStudent,
    String actorId = 'dashboard',
  }) async {
    if (failCreate) throw DecisionFailure('Rules deny lecture writes.');
    created.add(<String, Object?>{
      'subjectId': subjectId,
      'tab': tab,
      'title': title,
      'displayOrder': displayOrder,
      'publishDateTime': publishDateTime,
      'publishNow': publishNow,
      'guestEnabled': guestEnabled,
      'previewMinutes': previewMinutes,
      'resourceCount': resources.length,
      'resources': resources,
      'accessByStudent': accessByStudent,
    });
    return 'lec-new';
  }

  @override
  Future<int> nextLectureOrder({
    required String subjectId,
    required SubjectContentTab tab,
  }) async =>
      nextOrderResult;

  @override
  Future<void> renameSubject(String subjectId, String title) async {}

  @override
  Future<void> setSubjectVisible(String subjectId, bool visible) async {}

  @override
  Future<String> uploadLectureFile({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String lectureId,
    required String resourceId,
  }) async =>
      'lecture_resources/$lectureId/$resourceId/$fileName';

  @override
  Future<void> updateSubject(
    String subjectId, {
    String? title,
    String? gradeKey,
    String? coverUrl,
  }) async {}
}

const GradeStudentsData _roster = GradeStudentsData(
  gradeKey: 'grade_one',
  students: <GradeStudent>[
    GradeStudent(
      id: 's-ahmed',
      name: 'Ahmed',
      isCenter: true,
      plan: 'PRO',
      isActive: true,
      lastSignIn: '',
    ),
    GradeStudent(
      id: 's-mohamed',
      name: 'Mohamed',
      isCenter: true,
      plan: 'FREE',
      isActive: true,
      lastSignIn: '',
    ),
  ],
  pendingCount: 0,
  breakdown: <PlanBreakdownRow>[],
  isFallback: false,
);

Future<void> _pumpForm(
  WidgetTester tester,
  FakeLectureController fake,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subjectDetailsControllerProvider.overrideWithValue(fake),
        gradeStudentsProvider('grade_one')
            .overrideWith((ref) => Future.value(_roster)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => AddLectureOverlay.show(
                context,
                subjectId: 'sub-1',
                gradeKey: 'grade_one',
                tab: SubjectContentTab.lectures,
                initialOrder: 4,
                gradeColor: const Color(0xFFF59E0B),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Scrolls the form's scrollable so below-fold controls (Save actions,
/// guest row, access panel) receive pointer events in tests.
Future<void> _scrollFormDown(WidgetTester tester) async {
  final Finder scrollables = find.byType(SingleChildScrollView);
  expect(scrollables, findsWidgets);
  await tester.drag(scrollables.first, const Offset(0, -500));
  await tester.pumpAndSettle();
}

Future<void> _fillName(WidgetTester tester, String name) async {
  final Finder fields = find.byType(TextField);
  await tester.ensureVisible(fields.at(0));
  await tester.pumpAndSettle();
  await tester.enterText(fields.at(0), name);
  await tester.pumpAndSettle();
}

Future<void> _fillOrder(WidgetTester tester, String order) async {
  final Finder fields = find.byType(TextField);
  await tester.ensureVisible(fields.at(1));
  await tester.pumpAndSettle();
  await tester.enterText(fields.at(1), order);
  await tester.pumpAndSettle();
}

/// Stages one video resource through the real "+ Add Resource" flow.
/// The video dialog saves with its defaults (empty name -> 'Video').
Future<void> _stageVideoResource(WidgetTester tester) async {
  await tester.ensureVisible(find.text('+ Add Resource'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('+ Add Resource'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Video'));
  await tester.pumpAndSettle();
  // Two 'Save' texts exist while the video dialog is open (form + dialog);
  // the dialog lives in the overlay route above, so its Save comes last.
  await tester.tap(find.text('Save').last);
  await tester.pumpAndSettle();
}

void main() {
  group('AddLectureOverlay form', () {
    testWidgets('2. empty name is rejected', (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the lecture name.'), findsOneWidget);
      expect(fake.created, isEmpty);
    });

    testWidgets('3. display order starts empty with an 01 hint',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      final TextField orderField =
          tester.widget<TextField>(find.byType(TextField).at(1));
      expect(orderField.controller?.text, '');
      expect(orderField.decoration?.hintText, '01');
      await _fillName(tester, 'Algebra');
      await tester.enterText(find.byType(TextField).at(1), '0');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid display order.'), findsOneWidget);
      expect(fake.created, isEmpty);
      await tester.enterText(find.byType(TextField).at(1), '2');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(fake.created.single['displayOrder'], 2);
    });

    testWidgets('4/5. date picker selects a day and Save returns it',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      // Calendar popup is open (month grid with a day cell).
      expect(find.text('15'), findsWidgets);
      // Day tap only selects (highlight); the picker stays open.
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsOneWidget);
      // Save passes the date back; the field shows the mandated format.
      // Two 'Save' texts exist while the picker is open (form + picker);
      // the picker lives in the overlay route above, so its Save is last.
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsNothing);
      expect(find.text('Sept 15, 2026'), findsOneWidget);
    });

    testWidgets('date cancel preserves the previous value',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsOneWidget);
    });

    testWidgets('calendar header navigates months and years',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      // Interactive header: chevrons around month + year selectors.
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Sep'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      // Next month -> Oct 2026.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Oct'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      // Back twice -> Aug 2026.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Aug'), findsOneWidget);
      // Month dropdown jumps straight to Jan.
      await tester.tap(find.text('Aug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jan'));
      await tester.pumpAndSettle();
      expect(find.text('Jan'), findsOneWidget);
      // Year dropdown jumps straight to 2028.
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2028'));
      await tester.pumpAndSettle();
      expect(find.text('2028'), findsOneWidget);
      // Wrapping back from Jan 2028 lands on Dec 2027.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Dec'), findsOneWidget);
      expect(find.text('2027'), findsOneWidget);
      // Save returns the navigated date.
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Select Date'), findsNothing);
    });

    testWidgets('6/7. time picker opens and Set returns the time',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Time'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hourWheel')), findsOneWidget);
      expect(find.byKey(const Key('minuteWheel')), findsOneWidget);
      expect(find.byKey(const Key('periodWheel')), findsOneWidget);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Select Time'), findsNothing);
      expect(find.text('09:00 AM'), findsOneWidget);
    });

    testWidgets('time cancel preserves the previous value',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Select Time'), findsOneWidget);
    });

    testWidgets('8. date and time stay independent',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      // Reopen date, pick another day: time text must not change.
      await tester.tap(find.textContaining('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('09:00 AM'), findsOneWidget);
      // Reopen time shows the current selection (Set keeps it).
      await tester.tap(find.text('09:00 AM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(find.text('09:00 AM'), findsOneWidget);
    });

    testWidgets('9/11. Publish Now publishes; bottom Save does not',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _fillOrder(tester, '1');
      await _stageVideoResource(tester);
      await _scrollFormDown(tester);
      await tester.tap(find.text('Publish Now'));
      await tester.pumpAndSettle();
      expect(fake.created.single['publishNow'], isTrue);
      expect(find.text('Add New Lecture'), findsNothing);
    });

    testWidgets('10/11. Save Draft stays unpublished without a date',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _fillOrder(tester, '1');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save Draft'));
      await tester.pumpAndSettle();
      final Map<String, Object?> payload = fake.created.single;
      expect(payload['publishNow'], isFalse);
      expect(payload['publishDateTime'], isNull);
    });

    testWidgets('11. Save honors a scheduled date without publishing',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _fillOrder(tester, '1');
      await _stageVideoResource(tester);
      await tester.tap(find.text('Select Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final Map<String, Object?> payload = fake.created.single;
      expect(payload['publishNow'], isFalse);
      final DateTime? scheduled =
          payload['publishDateTime'] as DateTime?;
      expect(scheduled, isNotNull);
      expect(scheduled!.day, 15);
      expect(scheduled.hour, 9);
      expect(scheduled.minute, 0);
    });

    testWidgets('12. guest toggle enables Available Minutes',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      final Finder minutesFinder = find.byType(TextField).at(2);
      expect(tester.widget<TextField>(minutesFinder).enabled, isFalse);
      await _scrollFormDown(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(minutesFinder).enabled, isTrue);
    });

    testWidgets('13. minutes reject zero/negative values',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _scrollFormDown(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await _scrollFormDown(tester);
      await tester.enterText(find.byType(TextField).at(2), '0');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
          find.text('Available minutes must be greater than zero.'),
          findsOneWidget);
      expect(fake.created, isEmpty);
    });

    testWidgets('14. minutes map to the guest preview representation',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _scrollFormDown(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await _scrollFormDown(tester);
      await tester.enterText(find.byType(TextField).at(2), '7');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final Map<String, Object?> payload = fake.created.single;
      expect(payload['guestEnabled'], isTrue);
      expect(payload['previewMinutes'], 7);
    });

    testWidgets('15. Add Resource opens the four-type flow, no Quiz',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await tester.tap(find.text('+ Add Resource'));
      await tester.pumpAndSettle();
      expect(find.text('Add New Resource'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Attachment'), findsOneWidget);
      expect(find.text('External Link'), findsOneWidget);
      expect(find.text('Timeline Quiz'), findsNothing);
      // Video flow stages a Bunny-ID-only resource row. The dialog
      // contributes the last three TextFields (the form's own fields
      // sit beneath it in the tree).
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      expect(find.text('Add New Video'), findsOneWidget);
      final int fieldCount =
          find.byType(TextField).evaluate().length;
      final Finder fields =
          find.byType(TextField);
      await tester.enterText(
          fields.at(fieldCount - 3), 'Part 01');
      await tester.enterText(fields.at(fieldCount - 2), 'abc123');
      await tester.tap(find.byKey(const Key('resourceDialogSave')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Video - Part 01'), findsOneWidget);
    });

    testWidgets('16. Configure Access toggles persist per student',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController();
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Configure Access'));
      await tester.pumpAndSettle();
      expect(find.text('Ahmed'), findsOneWidget);
      expect(find.text('Mohamed'), findsOneWidget);
      // Deny Mohamed, save, and inspect the staged access map.
      final Finder switches = find.byType(Switch);
      await _scrollFormDown(tester);
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final Map<String, bool> access = fake
          .created.single['accessByStudent'] as Map<String, bool>;
      expect(access['s-ahmed'], isTrue);
      expect(access['s-mohamed'], isFalse);
    });

    testWidgets('save failure keeps the form open with an error',
        (WidgetTester tester) async {
      final FakeLectureController fake = FakeLectureController()
        ..failCreate = true;
      await _pumpForm(tester, fake);
      await _fillName(tester, 'Algebra');
      await _fillOrder(tester, '1');
      await _scrollFormDown(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Rules deny lecture writes.'), findsOneWidget);
      expect(find.text('Quick Upload'), findsOneWidget);
    });
  });

  group('SubjectDetailsScreen Add Lecture entry', () {
    testWidgets('1. Add Lecture opens the form from Subject Details',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final FakeLectureController fake = FakeLectureController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subjectDetailsControllerProvider.overrideWithValue(fake),
            subjectDetailsProvider('sub-1').overrideWith(
              (ref) => Stream.value(
                const SubjectDetails(
                    id: 'sub-1',
                    title: 'Math',
                    isVisible: true),
              ),
            ),
            for (final SubjectContentTab tab in SubjectContentTab.values)
              tabLecturesProvider((subjectId: 'sub-1', tab: tab))
                  .overrideWith((ref) =>
                      Stream.value(const <SubjectLecture>[])),
            gradeStudentsProvider('grade_one')
                .overrideWith((ref) => Future.value(_roster)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SubjectDetailsScreen(
                gradeKey: 'grade_one',
                subjectId: 'sub-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Lecture'));
      await tester.pumpAndSettle();
      expect(find.text('Quick Upload'), findsOneWidget);
      expect(find.text('Access for free Guest'), findsOneWidget);
      expect(find.text('Configure Access'), findsOneWidget);
    });
  });
}
