import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  HomeStats stats = const HomeStats(
    students: 12,
    subjects: 3,
    pendingApplications: 4,
    staff: 2,
  ),
  bool withError = false,
}) async {
  tester.view.physicalSize = const Size(1440, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeStatsProvider.overrideWith((ref) async {
          if (withError) throw Exception('offline');
          return stats;
        }),
      ],
      child: const MaterialApp(home: DashboardShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders sidebar sections and home analytics composition',
      (WidgetTester tester) async {
    await _pumpShell(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Grades'), findsOneWidget);
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Administrative'), findsOneWidget);
    expect(find.text('Reviewing Applications'), findsOneWidget);

    expect(find.text('Analytics & Reports'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Pending Applications'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('grades section expands into the four grades',
      (WidgetTester tester) async {
    await _pumpShell(tester);

    expect(find.text('Grade One'), findsNothing);
    await tester.tap(find.text('Grades'));
    await tester.pumpAndSettle();

    expect(find.text('Grade One'), findsOneWidget);
    expect(find.text('Grade Two'), findsOneWidget);
    expect(find.text('Grade Three'), findsOneWidget);
    expect(find.text('Grade Four'), findsOneWidget);
  });

  testWidgets('selecting a grade shows its section and keeps it expanded',
      (WidgetTester tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Grades'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade Two'));
    await tester.pumpAndSettle();

    expect(find.text('Grade Two'), findsNWidgets(2));
    expect(find.text('This section is coming next.'), findsOneWidget);
  });

  testWidgets('home stats surface a friendly message on failure',
      (WidgetTester tester) async {
    await _pumpShell(tester, withError: true);

    expect(
      find.text('Could not load platform stats. Please refresh later.'),
      findsOneWidget,
    );
  });
}
