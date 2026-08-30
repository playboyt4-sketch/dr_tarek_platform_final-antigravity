import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drtarek_dashboard/core/errors/failure.dart';
import 'package:drtarek_dashboard/features/authentication/domain/entities/dashboard_session.dart';
import 'package:drtarek_dashboard/features/authentication/domain/repositories/auth_repository.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/auth_providers.dart';
import 'package:drtarek_dashboard/features/authentication/presentation/providers/login_controller.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._handler);

  final DashboardSession Function(String phoneNumber, String password)
      _handler;

  int loginCalls = 0;
  int logoutCalls = 0;
  String? lastPhoneNumber;
  String? lastPassword;

  @override
  Future<DashboardSession> login({
    required String phoneNumber,
    required String password,
  }) async {
    loginCalls++;
    lastPhoneNumber = phoneNumber;
    lastPassword = password;
    return _handler(phoneNumber, password);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

DashboardSession _staffSession() => const DashboardSession(
      userId: 'u1',
      role: 'admin',
      approved: true,
    );

void main() {
  group('LoginController', () {
    test('successful staff login reaches LoginSuccess', () async {
      final repo = _FakeAuthRepository((_, _) => _staffSession());
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(loginControllerProvider.notifier).submit(
            phoneNumber: '01001234567',
            password: 'secret',
          );

      expect(container.read(loginControllerProvider), isA<LoginSuccess>());
      expect(repo.loginCalls, 1);
      expect(repo.lastPhoneNumber, '01001234567');
    });

    test('invalid phone format fails validation without calling backend',
        () async {
      final repo = _FakeAuthRepository((_, _) => _staffSession());
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(loginControllerProvider.notifier).submit(
            phoneNumber: '12345',
            password: 'secret',
          );

      final state = container.read(loginControllerProvider) as LoginFailure;
      expect(state.phoneError, isNotNull);
      expect(state.failure.code, FailureCode.validation);
      expect(repo.loginCalls, 0);
    });

    test('empty password fails validation without calling backend', () async {
      final repo = _FakeAuthRepository((_, _) => _staffSession());
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(loginControllerProvider.notifier).submit(
            phoneNumber: '01001234567',
            password: '',
          );

      final state = container.read(loginControllerProvider) as LoginFailure;
      expect(state.passwordError, isNotNull);
      expect(repo.loginCalls, 0);
    });

    test('wrong credentials surface as typed Failure, not raw exception',
        () async {
      final repo = _FakeAuthRepository(
        (_, _) => throw const Failure(FailureCode.wrongCredentials),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(loginControllerProvider.notifier).submit(
            phoneNumber: '01001234567',
            password: 'wrong',
          );

      final state = container.read(loginControllerProvider) as LoginFailure;
      expect(state.failure.code, FailureCode.wrongCredentials);
    });

    test('non-staff session is signed out and rejected', () async {
      final repo = _FakeAuthRepository(
        (_, _) => const DashboardSession(
          userId: 'u2',
          role: 'student',
          approved: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(loginControllerProvider.notifier).submit(
            phoneNumber: '01001234567',
            password: 'secret',
          );

      final state = container.read(loginControllerProvider) as LoginFailure;
      expect(state.failure.code, FailureCode.permissionDenied);
      expect(repo.logoutCalls, 1);
    });

    test('remember me is visual-only presentation state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(rememberMeProvider), isFalse);
      container.read(rememberMeProvider.notifier).set(true);
      expect(container.read(rememberMeProvider), isTrue);
    });
  });
}
