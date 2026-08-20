import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/routing/app_router.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/auth_gate.dart';

void main() {
  AuthUser testUser({
    String role = 'student',
    String approvalStatus = 'pending',
  }) {
    return AuthUser(
      id: 'user-1',
      fullName: 'Test User',
      phoneNumber: '01000000000',
      role: role,
      approvalStatus: approvalStatus,
      accountStatus: 'active',
    );
  }

  Future<void> pumpGate(WidgetTester tester, SessionState state) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AuthGate(sessionState: AsyncData<SessionState>(state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unauthenticated session reaches user type selection', (
    tester,
  ) async {
    await pumpGate(tester, const SessionUnauthenticated());

    expect(find.text('New Student'), findsOneWidget);
    expect(find.text('Current Student'), findsOneWidget);
  });

  testWidgets('student role reaches Student Home directly after login', (
    tester,
  ) async {
    final user = testUser(role: 'student', approvalStatus: 'approved');
    await pumpGate(
      tester,
      SessionAuthenticated(user: user, claims: const {'approved': true}),
    );

    // Student Home is the direct landing screen: greeting + 3-tab bottom nav.
    expect(find.text('Hi, Test'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  test('role mapping sends admin only to the existing admin destination', () {
    expect(authGateDestinationForRole('admin'), AuthGateDestination.admin);
    expect(authGateDestinationForRole('student'), AuthGateDestination.student);
  });

  testWidgets(
    'teacher role is explicitly blocked when no teacher destination exists',
    (tester) async {
      final user = testUser(role: 'teacher', approvalStatus: 'approved');
      await pumpGate(tester, SessionRoleBlocked(user: user, role: 'teacher'));

      expect(find.text('Access unavailable'), findsOneWidget);
      expect(find.text('لوحة الإدارة'), findsNothing);
    },
  );

  testWidgets('new_student role cannot receive normal platform access', (
    tester,
  ) async {
    final user = testUser(role: 'new_student', approvalStatus: 'approved');
    await pumpGate(tester, SessionRoleBlocked(user: user, role: 'new_student'));

      expect(find.text('Access unavailable'), findsOneWidget);
      expect(find.text('لوحة الإدارة'), findsNothing);
    });

  testWidgets('pending session cannot reach a protected destination', (
    tester,
  ) async {
    await pumpGate(tester, SessionPendingApproval(user: testUser()));

    expect(find.text('Account pending approval'), findsOneWidget);
    expect(find.text('New Student'), findsNothing);
  });

  testWidgets(
    'unauthorized device session cannot reach a protected destination',
    (tester) async {
      await pumpGate(tester, SessionUnauthorizedDevice(user: testUser()));

      expect(find.text('Unauthorized device'), findsOneWidget);
      expect(find.text('Current Student'), findsNothing);
    },
  );

  testWidgets(
    'AppRouter clears protected routes after session becomes unauthenticated',
    (tester) async {
      late _SwitchableSessionController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(() {
              controller = _SwitchableSessionController(
                SessionAuthenticated(
                  user: testUser(role: 'student', approvalStatus: 'approved'),
                  claims: const {'approved': true},
                ),
              );
              return controller;
            }),
          ],
          child: const MaterialApp(home: AppRouter()),
        ),
      );
      await tester.pumpAndSettle();

      final navigatorContext = tester.element(find.byType(AppRouter));
      Navigator.of(navigatorContext).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Protected Detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected Detail'), findsOneWidget);

      controller.setSession(const SessionUnauthenticated());
      await tester.pumpAndSettle();

      expect(find.text('Current Student'), findsOneWidget);
      expect(find.text('Protected Detail'), findsNothing);
      expect(find.text('New Student'), findsOneWidget);

      final didPop = await Navigator.of(navigatorContext).maybePop();
      await tester.pumpAndSettle();
      expect(didPop, isFalse);
      expect(find.text('Current Student'), findsOneWidget);
    },
  );

  testWidgets(
    'AppRouter uses the central session provider for unauthenticated routing',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(
              () => _FakeSessionController(const SessionUnauthenticated()),
            ),
          ],
          child: const MaterialApp(home: AppRouter()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current Student'), findsOneWidget);
    },
  );
}

class _SwitchableSessionController extends SessionController {
  SessionState current;

  _SwitchableSessionController(this.current);

  @override
  Future<SessionState> build() async => current;

  void setSession(SessionState next) {
    current = next;
    state = AsyncData(next);
  }
}

class _FakeSessionController extends SessionController {
  final SessionState session;

  _FakeSessionController(this.session);

  @override
  Future<SessionState> build() async => session;
}
