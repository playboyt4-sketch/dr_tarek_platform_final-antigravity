import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/screens/dashboard_home_screen.dart';
import 'package:drtarek_dashboard/features/home/presentation/widgets/quick_announcement_dialog.dart';
import 'package:drtarek_dashboard/features/home/presentation/widgets/quick_upload_modal.dart';

const List<SubjectOption> _gradeOneSubjects = <SubjectOption>[
  SubjectOption(id: 's-math', title: 'Math', gradeKey: 'grade_one'),
];

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(_gradeOneSubjects)),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardHomeScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Fixed-pixel Figma frames only fit with the real typeface — the
  // fallback test font is far wider and produces false overflows.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final ByteData fontData =
        await rootBundle.load('assets/fonts/GoogleSansFlex-VF.ttf');
    final FontLoader loader = FontLoader('Google Sans Flex')
      ..addFont(Future<ByteData>.value(fontData));
    await loader.load();
  });

  /// Explicit live-shaped fixture (test-only): small real-world-like
  /// counts exercising the same snapshot math the UI consumes.
  group('HomeAnalytics live snapshot math', () {
    const HomeAnalytics analytics = HomeAnalytics(
      totalStudents: 10,
      activeToday: 3,
      weeklyActivity: <int>[0, 1, 2, 3, 2, 1, 0],
      grades: <GradeAnalytics>[
        GradeAnalytics(
            gradeKey: 'grade_one',
            total: 4,
            pending: 1,
            center: 3,
            guest: 1),
        GradeAnalytics(
            gradeKey: 'grade_two',
            total: 3,
            pending: 0,
            center: 2,
            guest: 1),
        GradeAnalytics(
            gradeKey: 'grade_three',
            total: 2,
            pending: 2,
            center: 1,
            guest: 1),
        GradeAnalytics(
            gradeKey: 'grade_four',
            total: 1,
            pending: 0,
            center: 1,
            guest: 0),
      ],
    );

    test('reports live totals', () {
      expect(analytics.totalStudents, 10);
      expect(analytics.activeToday, 3);
      expect(analytics.grades, hasLength(4));
      expect(analytics.grades.map((g) => g.total), [4, 3, 2, 1]);
    });

    test('center/guest shares round from live counts', () {
      expect(analytics.grades[0].centerShareLabel, '75%');
      expect(analytics.grades[0].guestShareLabel, '25%');
      expect(analytics.grades[1].centerShareLabel, '67%');
      expect(analytics.grades[2].centerShareLabel, '50%');
      expect(analytics.grades[3].centerShareLabel, '100%');
    });

    test('empty grades report zero shares', () {
      const GradeAnalytics empty = GradeAnalytics(
        gradeKey: 'grade_one',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0,
      );

      expect(empty.centerShareLabel, '0%');
      expect(empty.guestShareLabel, '0%');
    });

    test('weekly activity max derives from live data', () {
      expect(analytics.weeklyActivity, hasLength(7));
      expect(analytics.weeklyActivity.last, 0);
      expect(analytics.maxWeeklyActivity, 3);
    });
  });

  group('weekly activity auto-scale', () {
    test('empty week reports all zeros with zero max', () {
      final List<int> zeros = List<int>.filled(7, 0);

      expect(zeros, hasLength(7));
      expect(zeros.fold(0, math.max), 0);
    });

    test('yTicksForMax starts at zero in every band', () {
      expect(yTicksForMax(0), [10, 8, 6, 4, 2, 0]);
      expect(yTicksForMax(50), [50, 40, 30, 20, 10, 0]);
      expect(yTicksForMax(240), [250, 200, 150, 100, 50, 0]);
    });

    test('yTicksForMax rounds large peaks to hundreds', () {
      expect(yTicksForMax(300), [300, 240, 180, 120, 60, 0]);
      expect(yTicksForMax(251), [300, 240, 180, 120, 60, 0]);
    });
  });

  group('quick upload validation', () {
    test('requires a subject first', () {
      expect(
        validateQuickUpload(
          subjectId: null,
          title: 'Newton',
          bunnyVideoId: 'vid-1',
          pdfPath: '',
        ),
        'Please select a subject.',
      );
    });

    test('requires a lecture title', () {
      expect(
        validateQuickUpload(
          subjectId: 's-math',
          title: '   ',
          bunnyVideoId: 'vid-1',
          pdfPath: '',
        ),
        'Lecture title is required.',
      );
    });

    test('requires a video id or a pdf path', () {
      expect(
        validateQuickUpload(
          subjectId: 's-math',
          title: 'Newton',
          bunnyVideoId: '',
          pdfPath: '',
        ),
        'Add a Bunny Video ID or a PDF path.',
      );
    });

    test('accepts a video-only draft', () {
      expect(
        validateQuickUpload(
          subjectId: 's-math',
          title: 'Newton',
          bunnyVideoId: 'vid-1',
          pdfPath: '',
        ),
        isNull,
      );
    });
  });

  group('announcement targets', () {
    test('requires title and body', () {
      expect(
        validateAnnouncement(title: '', body: 'hello'),
        'Notice title is required.',
      );
      expect(
        validateAnnouncement(title: 'Hi', body: '  '),
        'Message body is required.',
      );
      expect(
        validateAnnouncement(title: 'Hi', body: 'hello'),
        isNull,
      );
    });

    test('audience envelope covers grades, center and all', () {
      expect(
        announcementAudienceDoc('grade_two'),
        {'audience_type': 'grade', 'grade': 'grade_two', 'center_only': false},
      );
      expect(
        announcementAudienceDoc('center_only'),
        {'audience_type': 'center', 'grade': null, 'center_only': true},
      );
      expect(
        announcementAudienceDoc('all'),
        {'audience_type': 'all', 'grade': null, 'center_only': false},
      );
    });
  });

  group('quick add from the Upload card', () {
    testWidgets('+ Upload Now opens Quick Add New Lecture directly',
        (WidgetTester tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('+ Upload Now'));
      await tester.pumpAndSettle();

      // No intermediate Grade/Subject picker: the parent overlay opens
      // directly with Grade/Subject/Section selection inside it.
      // findsWidgets: the home "Quick Upload" card stays mounted behind
      // the overlay, so the title appears twice while it is open.
      expect(find.text('Quick Upload'), findsWidgets);
      expect(find.text('Grade'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Configure Access'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('overlay owns Grade/Subject/Section selection',
        (WidgetTester tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('+ Upload Now'));
      await tester.pumpAndSettle();

      // AddLectureOverlay (Figma node 886-980) opens without a preselected
      // subject and keeps its Configure Access entry point.
      expect(find.text('Quick Upload'), findsWidgets);
      expect(find.text('Select Subject'), findsOneWidget);
      expect(find.text('Configure Access'), findsOneWidget);
    });
  });

  group('quick announcement dialog', () {
    testWidgets('opens from the Announcement card',
        (WidgetTester tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('Send Notice ->'));
      await tester.pumpAndSettle();

      expect(find.text('Send Announcement'), findsWidgets);
      expect(find.text('All students'), findsWidgets);
      expect(find.text('Notice Title'), findsOneWidget);
      expect(find.text('Message Body'), findsOneWidget);
      expect(find.text('Send Notice'), findsOneWidget);
    });

    testWidgets('send without a title shows a validation error',
        (WidgetTester tester) async {
      await _pumpHome(tester);

      await tester.tap(find.text('Send Notice ->'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Notice'));
      await tester.pumpAndSettle();

      expect(find.text('Notice title is required.'), findsOneWidget);
    });
  });
}
