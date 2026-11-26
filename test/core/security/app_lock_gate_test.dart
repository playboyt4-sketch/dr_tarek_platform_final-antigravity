import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dr_tarek_platform/core/security/app_lock_gate.dart';
import 'package:dr_tarek_platform/core/security/biometric_lock_service.dart';
import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/profile/presentation/screens/student_profile_screen.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

class _ControlledBiometricClient implements BiometricAuthClient {
  bool supported;
  List<bool> scriptedResults;
  Completer<bool>? pendingAuth;
  int authCalls = 0;

  _ControlledBiometricClient({
    this.supported = true,
    List<bool>? scriptedResults,
  }) : scriptedResults = scriptedResults ?? <bool>[];

  @override
  Future<bool> get canCheckBiometrics async => supported;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  }) {
    authCalls++;
    if (pendingAuth != null && !pendingAuth!.isCompleted) {
      return pendingAuth!.future;
    }
    if (scriptedResults.isNotEmpty) {
      return Future<bool>.value(scriptedResults.removeAt(0));
    }
    return Future<bool>.value(true);
  }
}

class _MutableSessionController extends SessionController {
  SessionState _initial;
  _MutableSessionController(this._initial);

  @override
  Future<SessionState> build() async => _initial;

  void emit(SessionState next) {
    _initial = next;
    state = AsyncData<SessionState>(next);
  }
}

const AuthUser _student = AuthUser(
  id: 'student-1',
  fullName: 'Tarek Student',
  phoneNumber: '01098173500',
  role: 'student',
  studentType: 'center_student',
  grade: 'grade_four',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

const SessionAuthenticated _authenticated = SessionAuthenticated(
  user: _student,
  claims: <String, dynamic>{'role': 'student', 'approved': true},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AppLockGate', () {
    testWidgets(
      'locks on cold start when logged in and enabled, prompts automatically, and unlocks on success',
      (tester) async {
        final completer = Completer<bool>();
        final client = _ControlledBiometricClient()..pendingAuth = completer;
        final service = BiometricLockService(client: client, isWeb: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialBiometricLockEnabledProvider.overrideWithValue(true),
              biometricLockServiceProvider.overrideWithValue(service),
              sessionProvider.overrideWith(
                () => _MutableSessionController(_authenticated),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const AppLockGate(
                child: Scaffold(body: Text('HOME_CONTENT')),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsOneWidget);
        expect(find.text('Tarek el araby'), findsOneWidget);
        expect(client.authCalls, 1);

        completer.complete(true);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);
        expect(find.text('HOME_CONTENT'), findsOneWidget);
      },
    );

    testWidgets(
      'stays locked if Face ID fails/cancels and unlocks when user taps retry button',
      (tester) async {
        final client = _ControlledBiometricClient(scriptedResults: [false, true]);
        final service = BiometricLockService(client: client, isWeb: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialBiometricLockEnabledProvider.overrideWithValue(true),
              biometricLockServiceProvider.overrideWithValue(service),
              sessionProvider.overrideWith(
                () => _MutableSessionController(_authenticated),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const AppLockGate(
                child: Scaffold(body: Text('HOME_CONTENT')),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(client.authCalls, 1);
        expect(find.text('فتح باستخدام Face ID'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('app_lock_unlock_button')));
        await tester.pumpAndSettle();

        expect(client.authCalls, 2);
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);
      },
    );

    testWidgets(
      'locks after >30s in background and stays unlocked when <=30s',
      (tester) async {
        var fakeClock = DateTime(2026, 11, 27, 12, 0, 0);
        // First auth (cold start) succeeds, second auth (after >30s resume) stays pending/succeeds.
        final client = _ControlledBiometricClient(scriptedResults: [true, true]);
        final service = BiometricLockService(client: client, isWeb: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialBiometricLockEnabledProvider.overrideWithValue(true),
              biometricLockServiceProvider.overrideWithValue(service),
              sessionProvider.overrideWith(
                () => _MutableSessionController(_authenticated),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: AppLockGate(
                now: () => fakeClock,
                child: const Scaffold(body: Text('HOME_CONTENT')),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(client.authCalls, 1);
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);

        // Background for 20 seconds (<= 30s): should NOT lock.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        fakeClock = fakeClock.add(const Duration(seconds: 20));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(client.authCalls, 1);
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);

        // Background for 31 seconds (> 30s): MUST lock and auto-trigger auth.
        final resumeAuth = Completer<bool>();
        client.pendingAuth = resumeAuth;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        fakeClock = fakeClock.add(const Duration(seconds: 31));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsOneWidget);
        expect(client.authCalls, 2);

        resumeAuth.complete(true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);
      },
    );

    testWidgets(
      'does not lock when unauthenticated and resets lock state on logout',
      (tester) async {
        var fakeClock = DateTime(2026, 11, 27, 12, 0, 0);
        final sessionCtrl = _MutableSessionController(_authenticated);
        final client = _ControlledBiometricClient()
          ..pendingAuth = Completer<bool>();
        final service = BiometricLockService(client: client, isWeb: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialBiometricLockEnabledProvider.overrideWithValue(true),
              biometricLockServiceProvider.overrideWithValue(service),
              sessionProvider.overrideWith(() => sessionCtrl),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: AppLockGate(
                now: () => fakeClock,
                child: const Scaffold(body: Text('HOME_CONTENT')),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsOneWidget);

        // Simulate logout: must clear lock immediately without requiring Face ID.
        sessionCtrl.emit(const SessionUnauthenticated());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);

        // Background resume while logged out must never trigger lock.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        fakeClock = fakeClock.add(const Duration(seconds: 45));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(client.authCalls, 1);
        expect(find.byKey(const ValueKey('app_lock_unlock_button')), findsNothing);
      },
    );
  });

  group('StudentProfileScreen Face ID toggle', () {
    testWidgets(
      'hides toggle when biometrics unsupported and verifies Face ID before saving when supported',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // 1. Unsupported device -> toggle is hidden.
        final unsupportedService = BiometricLockService(
          client: _ControlledBiometricClient(supported: false),
          isWeb: false,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              biometricLockServiceProvider.overrideWithValue(unsupportedService),
              dashboardSubjectsProvider.overrideWith(
                (ref) => Stream.value(const <DashboardSubject>[]),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: StudentProfileScreen(user: _student),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('قفل التطبيق بـ Face ID / البصمة'), findsNothing);

        // 2. Supported device -> toggle appears, fails first then succeeds.
        final client = _ControlledBiometricClient(
          supported: true,
          scriptedResults: [false, true],
        );
        final supportedService = BiometricLockService(client: client, isWeb: false);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              biometricLockServiceProvider.overrideWithValue(supportedService),
              dashboardSubjectsProvider.overrideWith(
                (ref) => Stream.value(const <DashboardSubject>[]),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: StudentProfileScreen(user: _student),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const ValueKey('biometric_lock_switch'));
        expect(find.text('قفل التطبيق بـ Face ID / البصمة'), findsOneWidget);
        expect(switchFinder, findsOneWidget);

        // First attempt: Face ID fails -> switch remains OFF and not saved.
        await tester.ensureVisible(switchFinder);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        expect(client.authCalls, 1);
        expect(await supportedService.isLockEnabled(), isFalse);
        expect(tester.widget<Switch>(switchFinder).value, isFalse);

        // Second attempt: Face ID succeeds -> switch turns ON and persists.
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        expect(client.authCalls, 2);
        expect(await supportedService.isLockEnabled(), isTrue);
        expect(tester.widget<Switch>(switchFinder).value, isTrue);
      },
    );
  });
}
