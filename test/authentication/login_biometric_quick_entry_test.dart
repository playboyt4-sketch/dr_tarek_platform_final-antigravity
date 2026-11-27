import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dr_tarek_platform/core/routing/app_routes.dart';
import 'package:dr_tarek_platform/core/security/biometric_lock_service.dart';
import 'package:dr_tarek_platform/core/theme/app_theme.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/auth_repository.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/screens/login_screen.dart';
import 'package:dr_tarek_platform/features/student_dashboard/domain/entities/dashboard_subject.dart';
import 'package:dr_tarek_platform/features/student_dashboard/presentation/providers/dashboard_providers.dart';
import 'package:dr_tarek_platform/l10n/generated/app_localizations.dart';

class _FakeBiometricClient implements BiometricAuthClient {
  int authCalls = 0;
  bool nextResult = true;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  }) async {
    authCalls++;
    return nextResult;
  }
}

class _CountingAuthRepo implements AuthRepository {
  int loginCalls = 0;

  @override
  Future<void> applySessionPersistence({required bool rememberMe}) async {}

  @override
  Future<AuthUser?> getCurrentUser() async => _student;

  @override
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory() async => const [];

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) async {
    loginCalls++;
    return _student;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
    String? fcmToken,
    String? deviceId,
    String? platform,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AuthUser> staffLogin({
    required String displayName,
    required String password,
  }) async =>
      throw UnimplementedError();
}

class _FixedSessionController extends SessionController {
  @override
  Future<SessionState> build() async => const SessionAuthenticated(
        user: _student,
        claims: <String, dynamic>{'role': 'student', 'approved': true},
      );
}

const AuthUser _student = AuthUser(
  id: 'student-1',
  fullName: 'Tarek Student',
  phoneNumber: '01098173500',
  role: 'student',
  approvalStatus: 'approved',
  accountStatus: 'active',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'LoginScreen shows Face ID quick login for saved session and enters Home without redundant backend login',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final bioClient = _FakeBiometricClient();
      final bioService = BiometricLockService(client: bioClient, isWeb: false);
      final authRepo = _CountingAuthRepo();

      final router = GoRouter(
        initialLocation: AppRoutes.loginPath,
        routes: [
          GoRoute(
            path: AppRoutes.loginPath,
            name: AppRoutes.login,
            builder: (_, _) => const LoginScreen(),
          ),
          GoRoute(
            path: AppRoutes.studentHomePath,
            name: AppRoutes.studentHome,
            builder: (_, _) => const Scaffold(body: Text('HOME_REACHED')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepo),
            sessionProvider.overrideWith(_FixedSessionController.new),
            initialBiometricLockEnabledProvider.overrideWithValue(true),
            biometricLockServiceProvider.overrideWithValue(bioService),
            dashboardSubjectsProvider.overrideWith(
              (ref) => Stream.value(const <DashboardSubject>[]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bioBtn = find.byKey(const ValueKey('biometricQuickLoginButton'));
      expect(bioBtn, findsOneWidget);
      expect(find.text('01098173500'), findsOneWidget);

      await tester.tap(bioBtn);
      await tester.pumpAndSettle();

      expect(bioClient.authCalls, 1);
      expect(authRepo.loginCalls, 0);
      expect(find.text('HOME_REACHED'), findsOneWidget);
    },
  );
}
