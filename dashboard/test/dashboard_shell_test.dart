import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';
import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/core/widgets/animated_menu_button.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';

const GradeStudentsData _gradeTwoData = GradeStudentsData(
  gradeKey: 'grade_two',
  students: <GradeStudent>[
    GradeStudent(
      id: 's1',
      name: 'Omar khaled hassan',
      isCenter: false,
      plan: 'FREE',
      isActive: true,
      lastSignIn: '11/8/2026',
    ),
  ],
  pendingCount: 9,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 152, share: 40),
    PlanBreakdownRow(label: 'PRO', count: 144, share: 38),
    PlanBreakdownRow(label: 'MAX', count: 38, share: 10),
    PlanBreakdownRow(label: 'Guest', count: 46, share: 12),
  ],
  isFallback: false,
);

const GradeStudentsData _gradeOneData = GradeStudentsData(
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

Future<void> _pumpShell(
  WidgetTester tester, {
  List<SubjectOption> gradeTwoSubjects = const <SubjectOption>[],
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Pin the Figma fallback: the app default serves mock students,
        // but this test asserts the fallback composition specifically.
        homeAnalyticsProvider
            .overrideWith((ref) => Future.value(HomeAnalytics.fallback())),
        gradeSubjectsProvider('grade_two')
            .overrideWith((ref) => Stream.value(gradeTwoSubjects)),
        gradeStudentsProvider('grade_two')
            .overrideWith((ref) => Future.value(_gradeTwoData)),
        gradeStudentsProvider('grade_one')
            .overrideWith((ref) => Future.value(_gradeOneData)),
      ],
      child: const MaterialApp(home: DashboardShell()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Open menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders home analytics composition with Figma numbers',
      (WidgetTester tester) async {
    await _pumpShell(tester);

    // Header.
    expect(find.byType(TheMenuButton), findsOneWidget);
    expect(find.textContaining('Tarek el araby'), findsWidgets);
    expect(find.textContaining('Platform'), findsWidgets);

    // Pie + total (dynamic shares from real counts: 450/380/260/150).
    expect(find.text('Total Students'), findsWidgets);
    expect(find.text('1240'), findsOneWidget);
    expect(find.text('36%'), findsOneWidget);
    expect(find.text('31%'), findsOneWidget);
    expect(find.text('21%'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);

    // Grade breakdown cards.
    expect(find.text('Grade One'), findsOneWidget);
    expect(find.text('Grade Two'), findsOneWidget);
    expect(find.text('Grade Three'), findsOneWidget);
    expect(find.text('Grade Four'), findsOneWidget);
    expect(find.text('450'), findsOneWidget);
    expect(find.text('380'), findsOneWidget);
    expect(find.text('260'), findsOneWidget);
    // Grade Four total shares its label with the auto-scaled Y tick.
    expect(find.text('150'), findsNWidgets(2));
    expect(find.text('Pending 7'), findsOneWidget);
    expect(find.textContaining('Center 396'), findsOneWidget);

    // Bottom section.
    expect(find.text('Upload Lecture'), findsOneWidget);
    expect(
      find.text('Add new video, PDFs & assign to grades'),
      findsOneWidget,
    );
    expect(find.text('+ Upload Now'), findsOneWidget);
    expect(find.text('Send Announcement'), findsOneWidget);
    expect(
      find.text('Broadcast notifications to students'),
      findsOneWidget,
    );
    expect(find.text('Send Notice ->'), findsOneWidget);
    expect(find.text('Student Activity'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    // Auto-scaled Y-axis (fallback weekly max 240 → ceiling 250):
    // each grid line and its number share ONE centered Row, so all are
    // Text widgets. "240" is the counter only; "150" is asserted above.
    expect(find.text('240'), findsOneWidget);
    for (final String tick in <String>['250', '200', '100', '50']) {
      expect(find.text(tick), findsOneWidget);
    }
    expect(find.text('Active Today'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Fri'), findsOneWidget);
  });

  testWidgets('menu button opens the full menu overlay',
      (WidgetTester tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Grades'), findsOneWidget);
    expect(find.text('Management'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.text('Grade Three'),
      ),
      findsOneWidget,
    );
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Admins'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('Audit Logs'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('System Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Close menu'), findsOneWidget);
  });

  testWidgets('selecting a grade opens its students screen and closes the menu',
      (WidgetTester tester) async {
    await _pumpShell(
      tester,
      gradeTwoSubjects: const <SubjectOption>[
        SubjectOption(id: 's-phy', title: 'Physics', gradeKey: 'grade_two'),
      ],
    );
    await _openMenu(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.text('Grade Two'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Students'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Omar khaled hassan'), findsOneWidget);
    expect(find.text('Review Pending Requests'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    // Menu auto-closed.
    expect(find.text('Management'), findsNothing);
  });

  testWidgets('pending CTA opens the grade pending-requests screen',
      (WidgetTester tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.text('Grade One'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review Pending Requests'));
    await tester.pumpAndSettle();

    expect(find.text('Pending Requests'), findsOneWidget);
    expect(find.text('Ahmed gamal mousa'), findsOneWidget);
    expect(find.text('01101011588'), findsOneWidget);
    expect(find.text('I phone 15 pro'), findsWidgets);
    expect(find.text('3/9/2026'), findsOneWidget);
  });

  testWidgets('close button returns to the previous screen',
      (WidgetTester tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(find.bySemanticsLabel('Close menu'));
    await tester.pumpAndSettle();

    expect(find.text('Student Activity'), findsOneWidget);
    expect(find.text('Management'), findsNothing);
  });

  testWidgets('management entries open placeholder sections',
      (WidgetTester tester) async {
    await _pumpShell(tester);
    await _openMenu(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(DashboardFullMenu),
        matching: find.text('Payments'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('This section is coming next.'), findsOneWidget);
  });
}
