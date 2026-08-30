import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/localization/locale_controller.dart';
import 'package:dr_tarek_platform/core/routing/app_router.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/auth_gate.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

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
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
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

    expect(find.text('طالب جديد'), findsOneWidget);
    expect(find.text('طالب حالي'), findsOneWidget);
  });

  testWidgets('student role reaches Student Home directly after login', (
    tester,
  ) async {
    final user = testUser(role: 'student', approvalStatus: 'approved');
    await pumpGate(
      tester,
      SessionAuthenticated(user: user, claims: const {'approved': true}),
    );

    // Student Home is the direct landing screen: greeting + 2-tab bottom nav
    // (chat was removed from the current phase).
    expect(find.text('Hi, Test'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
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

      expect(find.text('الدور غير متاح'), findsOneWidget);
      expect(find.text('لوحة الإدارة'), findsNothing);
    },
  );

  testWidgets('new_student role cannot receive normal platform access', (
    tester,
  ) async {
    final user = testUser(role: 'new_student', approvalStatus: 'approved');
    await pumpGate(tester, SessionRoleBlocked(user: user, role: 'new_student'));

    expect(find.text('الدور غير متاح'), findsOneWidget);
    expect(find.text('لوحة الإدارة'), findsNothing);
  });

  testWidgets('pending session cannot reach a protected destination', (
    tester,
  ) async {
    await pumpGate(tester, SessionPendingApproval(user: testUser()));

    expect(find.text('الحساب بانتظار الموافقة'), findsOneWidget);
    expect(find.text('طالب جديد'), findsNothing);
  });

  testWidgets(
    'unauthorized device session cannot reach a protected destination',
    (tester) async {
      await pumpGate(tester, SessionUnauthorizedDevice(user: testUser()));

      expect(find.text('جهاز غير مصرح به'), findsOneWidget);
      expect(find.text('طالب حالي'), findsNothing);
    },
  );

  testWidgets(
    'session error renders a localized friendly message instead of raw text',
    (tester) async {
      await pumpGateWithSessionError(tester);

      // The raw exception text must never appear on screen.
      expect(find.textContaining('RawBoom'), findsNothing);
      expect(find.text('خطأ في الجلسة'), findsOneWidget);
      expect(find.text('حدث خطأ غير متوقع، حاول مرة أخرى.'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    },
  );

  testWidgets(
    'AppRouter clears protected routes after session becomes unauthenticated',
    (tester) async {
      final controller = _SwitchableSessionController(
        SessionAuthenticated(
          user: testUser(role: 'student', approvalStatus: 'approved'),
          claims: const {'approved': true},
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialLocaleProvider.overrideWithValue(const Locale('ar')),
            sessionProvider.overrideWith(() => controller),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const AppRouter(),
          ),
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

      expect(find.text('طالب حالي'), findsOneWidget);
      expect(find.text('Protected Detail'), findsNothing);
      expect(find.text('طالب جديد'), findsOneWidget);

      final didPop = await Navigator.of(navigatorContext).maybePop();
      await tester.pumpAndSettle();
      expect(didPop, isFalse);
      expect(find.text('طالب حالي'), findsOneWidget);
    },
  );

  testWidgets(
    'AppRouter uses the central session provider for unauthenticated routing',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialLocaleProvider.overrideWithValue(const Locale('ar')),
            sessionProvider.overrideWith(
              () => _FakeSessionController(const SessionUnauthenticated()),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const AppRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('طالب حالي'), findsOneWidget);
    },
  );
}

Future<void> pumpGateWithSessionError(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AuthGate(
          sessionState: AsyncError<SessionState>(
            StateError('RawBoom failure detail'),
            StackTrace.current,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
