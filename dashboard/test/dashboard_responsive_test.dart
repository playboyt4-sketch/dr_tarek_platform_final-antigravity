import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/core/responsive/responsive.dart';
import 'package:drtarek_dashboard/core/widgets/animated_menu_button.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';

const HomeAnalytics _analytics = HomeAnalytics(
  totalStudents: 42,
  activeToday: 12,
  weeklyActivity: <int>[4, 6, 8, 5, 9, 11, 12],
  grades: <GradeAnalytics>[
    GradeAnalytics(
      gradeKey: 'grade_one',
      total: 15,
      pending: 2,
      center: 10,
      guest: 5,
    ),
    GradeAnalytics(
      gradeKey: 'grade_two',
      total: 12,
      pending: 1,
      center: 8,
      guest: 4,
    ),
    GradeAnalytics(
      gradeKey: 'grade_three',
      total: 9,
      pending: 0,
      center: 6,
      guest: 3,
    ),
    GradeAnalytics(
      gradeKey: 'grade_four',
      total: 6,
      pending: 1,
      center: 4,
      guest: 2,
    ),
  ],
);

const GradeStudentsData _gradeOneData = GradeStudentsData(
  gradeKey: 'grade_one',
  students: <GradeStudent>[
    GradeStudent(
      id: 's1',
      name: 'Youssef Mohamed Ali',
      isCenter: true,
      isActive: true,
      lastSignIn: '12/8/2026',
    ),
  ],
  pendingCount: 2,
  breakdown: <PlanBreakdownRow>[
    PlanBreakdownRow(label: 'Free', count: 1, share: 100),
  ],
  isFallback: false,
);

Future<void> _pumpShellAtSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeAnalyticsProvider.overrideWith((ref) => Future.value(_analytics)),
        gradeStudentsProvider('grade_one')
            .overrideWith((ref) => Future.value(_gradeOneData)),
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
      ],
      child: const MaterialApp(home: DashboardShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('breakpointForWidth classifies mobile, tablet, and desktop', () {
    expect(breakpointForWidth(375), DashboardBreakpoint.mobile);
    expect(breakpointForWidth(767), DashboardBreakpoint.mobile);
    expect(breakpointForWidth(768), DashboardBreakpoint.tablet);
    expect(breakpointForWidth(1100), DashboardBreakpoint.tablet);
    expect(breakpointForWidth(1101), DashboardBreakpoint.desktop);
    expect(breakpointForWidth(1440), DashboardBreakpoint.desktop);
  });

  testWidgets('mobile (<768px) uses AppBar + Drawer without FittedBox scaling',
      (WidgetTester tester) async {
    await _pumpShellAtSize(tester, const Size(375, 812));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TheMenuButton), findsNothing);
    expect(find.text('Grade One'), findsOneWidget);
    expect(find.text('Quick Upload'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Open Drawer via AppBar menu icon and navigate to Grade One.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Grade One'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Youssef Mohamed Ali'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet (820x1024) renders full-viewport shell without overflow',
      (WidgetTester tester) async {
    await _pumpShellAtSize(tester, const Size(820, 1024));

    expect(find.byType(TheMenuButton), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.getSize(find.byType(DashboardShell)), const Size(820, 1024));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop (1440x900) expands to full screen width',
      (WidgetTester tester) async {
    await _pumpShellAtSize(tester, const Size(1440, 900));

    expect(find.byType(TheMenuButton), findsOneWidget);
    expect(tester.getSize(find.byType(DashboardShell)), const Size(1440, 900));
    expect(tester.takeException(), isNull);
  });
}
