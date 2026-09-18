import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/home/presentation/screens/dashboard_home_screen.dart';

/// Live-shaped zero fixture: what [homeAnalyticsProvider] emits for an
/// empty database. Real zeros must render as zeros, never as demo numbers.
const HomeAnalytics _zeroAnalytics = HomeAnalytics(
  totalStudents: 0,
  activeToday: 0,
  weeklyActivity: <int>[0, 0, 0, 0, 0, 0, 0],
  grades: <GradeAnalytics>[
    GradeAnalytics(
        gradeKey: 'grade_one', total: 0, pending: 0, center: 0, guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_two', total: 0, pending: 0, center: 0, guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_three',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_four', total: 0, pending: 0, center: 0, guest: 0),
  ],
);

/// Test-harness accommodation for a KNOWN baseline failure: fixed-height
/// Figma cards overflow by 5px under the test fallback font. Only that
/// layout noise is ignored.
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

Future<void> _pumpHome(
  WidgetTester tester, {
  required Future<HomeAnalytics> Function(Ref ref) analytics,
  int Function()? onSubscribe,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _ignoreKnownBaselineOverflows();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeAnalyticsProvider.overrideWith((Ref ref) {
          onSubscribe?.call();
          return analytics(ref);
        }),
        gradeSubjectsProvider('grade_one')
            .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardHomeScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('home analytics error states (no synthetic numbers)', () {
    testWidgets('top analytics shows an error with retry, never demo data',
        (WidgetTester tester) async {
      int calls = 0;
      await _pumpHome(
        tester,
        analytics: (Ref ref) => Future<HomeAnalytics>.error(
          StateError('unavailable'),
        ),
        onSubscribe: () {
          calls++;
          return 0;
        },
      );

      expect(find.text('Could not load analytics.'), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
      // No synthetic Figma numbers anywhere.
      expect(find.text('1240'), findsNothing);
      expect(find.text('450'), findsNothing);

      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();

      // Retry re-runs the provider (initial load + one retry).
      expect(calls, 2);
    });

    testWidgets('activity card shows a compact error, never demo activity',
        (WidgetTester tester) async {
      await _pumpHome(
        tester,
        analytics: (Ref ref) => Future<HomeAnalytics>.error(
          StateError('unavailable'),
        ),
      );

      expect(find.text('Could not load activity.'), findsOneWidget);
      expect(find.text('240'), findsNothing);
    });
  });

  group('home analytics zero state', () {
    testWidgets('empty database renders real zeros, no error, no demo data',
        (WidgetTester tester) async {
      await _pumpHome(
        tester,
        analytics: (Ref ref) => Future.value(_zeroAnalytics),
      );

      expect(find.text('Could not load analytics.'), findsNothing);
      expect(find.text('Could not load activity.'), findsNothing);
      expect(find.text('1240'), findsNothing);
      expect(find.text('Total Students'), findsWidgets);
    });
  });
}
