import 'package:dr_tarek_platform/core/routing/app_routes.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/splash_screen.dart';
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
      'SplashScreen skips 5.8s hold and routes directly to studentHome when session is already authenticated',
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
          builder: (_, _) => const Scaffold(body: Text('User Type Selection')),
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

    // Pump only a brief duration (< 5.8s) — authenticated users go straight
    // to Student Home immediately without waiting for the 5.8s hold.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Student Home Ready'), findsOneWidget);
    expect(find.text('User Type Selection'), findsNothing);
  });
}
