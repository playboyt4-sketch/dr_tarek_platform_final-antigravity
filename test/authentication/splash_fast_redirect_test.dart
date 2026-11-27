import 'package:dr_tarek_platform/core/routing/app_routes.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/splash_screen.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _ReadySessionController extends SessionController {
  final SessionState value;

  _ReadySessionController(this.value);

  @override
  Future<SessionState> build() async => value;
}

void main() {
  testWidgets(
    'SplashScreen never skips directly to Home and routes to UserTypeSelection after ~1.6s',
    (WidgetTester tester) async {
      final user = AuthUser(
        id: 'student-1',
        fullName: 'Student',
        phoneNumber: '01000000000',
        role: 'student',
        approvalStatus: 'approved',
        accountStatus: 'active',
      );
      final router = GoRouter(
        initialLocation: AppRoutes.splashPath,
        routes: [
          GoRoute(
            path: AppRoutes.splashPath,
            name: AppRoutes.splash,
            builder: (_, _) => const SplashScreen(),
          ),
          GoRoute(
            path: AppRoutes.userTypeSelectionPath,
            name: AppRoutes.userTypeSelection,
            builder: (_, _) =>
                const Scaffold(body: Text('User Type Selection')),
          ),
          GoRoute(
            path: AppRoutes.studentHomePath,
            name: AppRoutes.studentHome,
            builder: (_, _) => const Scaffold(body: Text('Student Home Ready')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardSubjectsProvider.overrideWith(
              (ref) => Stream.value(const <DashboardSubject>[]),
            ),
            sessionProvider.overrideWith(
              () => _ReadySessionController(
                SessionAuthenticated(
                  user: user,
                  claims: const {'approved': true, 'role': 'student'},
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      // Briefly after mount: must remain on Splash (never jump directly to Home).
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Student Home Ready'), findsNothing);
      expect(find.text('User Type Selection'), findsNothing);

      // After 1.6s: transitions smoothly to User Type Selection.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      expect(find.text('User Type Selection'), findsOneWidget);
      expect(find.text('Student Home Ready'), findsNothing);
    },
  );
}
