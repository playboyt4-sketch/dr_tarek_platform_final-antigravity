import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/app/shell/dashboard_full_menu.dart';
import 'package:drtarek_dashboard/app/shell/dashboard_shell.dart';
import 'package:drtarek_dashboard/core/theme/app_typography.dart';
import 'package:drtarek_dashboard/features/applications/presentation/providers/application_decision_provider.dart';
import 'package:drtarek_dashboard/features/authentication/domain/repositories/auth_repository.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/home/presentation/providers/home_stats_provider.dart';
import 'package:drtarek_dashboard/features/students/presentation/providers/grade_students_provider.dart';

/// Voluntary Sign Out in the shell management menu (Phase G0).
///
/// Text-only red entry below System Settings, same menu typography,
/// wired to the existing `authRepositoryProvider.logout()`.

class _FakeAuthRepository implements AuthRepository {
  int logoutCalls = 0;

  @override
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

const GradeStudentsData _emptyGradeData = GradeStudentsData(  gradeKey: 'grade_two',
  students: <GradeStudent>[],
  pendingCount: 0,
  breakdown: <PlanBreakdownRow>[],
  isFallback: true,
);

/// Live-shaped zero fixture: what [homeAnalyticsProvider] emits for an
/// empty database. Analytics content is irrelevant to sign-out assertions.
const HomeAnalytics _zeroAnalytics = HomeAnalytics(
  totalStudents: 0,
  activeToday: 0,
  weeklyActivity: <int>[0, 0, 0, 0, 0, 0, 0],
  grades: <GradeAnalytics>[
    GradeAnalytics(
        gradeKey: 'grade_one',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_two',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_three',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0),
    GradeAnalytics(
        gradeKey: 'grade_four',
        total: 0,
        pending: 0,
        center: 0,
        guest: 0),
  ],
);

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

Future<void> _pumpMenu(
  WidgetTester tester, {
  VoidCallback? onSignOut,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardFullMenu(
          onClose: () {},
          onNavigate: (_) {},
          onSignOut: onSignOut,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Sign Out menu entry', () {
    testWidgets('renders below System Settings when wired', (tester) async {
      await _pumpMenu(tester, onSignOut: () {});

      final Finder signOut = find.text('Sign Out');
      expect(signOut, findsOneWidget);

      final Offset signOutTop =
          tester.getTopLeft(signOut);
      final Offset settingsTop =
          tester.getTopLeft(find.text('System Settings'));
      expect(signOutTop.dy, greaterThan(settingsTop.dy));
    });

    testWidgets('absent when no sign-out handler is provided', (tester) async {
      await _pumpMenu(tester);

      expect(find.text('Sign Out'), findsNothing);
    });

    testWidgets('uses menu typography in error-ink red, text only, no icon',
        (tester) async {
      await _pumpMenu(tester, onSignOut: () {});

      final TextStyle signOutStyle =
          tester.widget<Text>(find.text('Sign Out')).style!;
      final TextStyle itemStyle =
          tester.widget<Text>(find.text('System Settings')).style!;
      expect(signOutStyle.fontSize, itemStyle.fontSize);
      expect(signOutStyle.fontWeight, itemStyle.fontWeight);
      expect(signOutStyle.fontFamily, itemStyle.fontFamily);
      expect(signOutStyle.color, AppColors.errorInk);

      expect(
        find.descendant(
          of: find.byType(DashboardFullMenu),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
    });

    testWidgets('tap fires the wired sign-out callback', (tester) async {
      int calls = 0;
      await _pumpMenu(
        tester,
        onSignOut: () {
          calls++;
        },
      );

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  });

  group('Shell sign-out wiring', () {
    testWidgets('menu Sign Out calls authRepositoryProvider.logout()',
        (tester) async {
      final _FakeAuthRepository repo = _FakeAuthRepository();
      tester.view.physicalSize = const Size(1920, 1440);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _ignoreKnownBaselineOverflows();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(
              const AsyncData<DashboardSession?>(
                DashboardSession(
                    userId: 'd1', role: 'doctor', approved: true),
              ),
            ),
            authRepositoryProvider.overrideWithValue(repo),
            homeAnalyticsProvider
                .overrideWith((ref) => Future.value(_zeroAnalytics)),
            gradeSubjectsProvider('grade_two')
                .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
            gradeSubjectsProvider('grade_one')
                .overrideWith((ref) => Stream.value(const <SubjectOption>[])),
            gradeStudentsProvider('grade_two')
                .overrideWith((ref) => Future.value(_emptyGradeData)),
            gradeStudentsProvider('grade_one')
                .overrideWith((ref) => Future.value(_emptyGradeData)),
          ],
          child: const MaterialApp(home: DashboardShell()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Sign Out'), findsOneWidget);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      expect(repo.logoutCalls, 1);
    });
  });
}
