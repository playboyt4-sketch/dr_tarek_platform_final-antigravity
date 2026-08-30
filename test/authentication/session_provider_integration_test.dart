import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dr_tarek_platform/core/di/auth_providers.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/auth_user.dart';
import 'package:dr_tarek_platform/features/authentication/domain/repositories/auth_repository.dart';
import 'package:dr_tarek_platform/features/authentication/domain/entities/session_state.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/auth_provider.dart';
import 'package:dr_tarek_platform/features/authentication/presentation/providers/session_provider.dart';
import 'package:dr_tarek_platform/features/device_binding/domain/entities/device_info.dart';
import 'package:dr_tarek_platform/features/device_binding/domain/repositories/device_binding_repository.dart';
import 'package:dr_tarek_platform/features/device_binding/presentation/providers/device_binding_provider.dart';

void main() {
  final approvedUser = AuthUser(
    id: 'user-1',
    fullName: 'Approved User',
    phoneNumber: '01000000000',
    role: 'student',
    approvalStatus: 'approved',
    accountStatus: 'active',
  );

  const approvedClaims = <String, dynamic>{'approved': true, 'role': 'student'};

  Future<ProviderContainer> createContainer({
    required AuthUser? currentUser,
    required Map<String, dynamic> claims,
    required FakeDeviceBindingRepository deviceRepository,
  }) async {
    final authRepository = FakeAuthRepository(currentUser: currentUser);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        customClaimsProvider.overrideWith((ref) {
          final claimsController = StreamController<Map<String, dynamic>?>(sync: true);
          claimsController.add(claims);
          ref.onDispose(() => claimsController.close());
          return claimsController.stream;
        }),
        deviceBindingRepositoryProvider.overrideWithValue(deviceRepository),
      ],
    );
    addTearDown(() {
      container.dispose();
    });

    // Ensure the async notifier finishes its initial build
    await container.read(authProvider.future);

    // Mirror production: AuthGate actively listens to the session provider.
    // In Riverpod 3 every provider is auto-dispose once its last listener
    // drops, so bare `container.read(.future)` would let the whole session
    // graph be disposed mid-bootstrap.
    container.listen(sessionProvider, (_, _) {});

    return container;
  }

  test('allowed Device Binding result reaches authenticated session', () async {
    final container = await createContainer(
      currentUser: approvedUser,
      claims: approvedClaims,
      deviceRepository: FakeDeviceBindingRepository(allowed: true),
    );

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SessionAuthenticated>());
    expect((state as SessionAuthenticated).claims['approved'], isTrue);
  });

  test(
    'denied Device Binding result reaches unauthorizedDevice session',
    () async {
      final container = await createContainer(
        currentUser: approvedUser,
        claims: approvedClaims,
        deviceRepository: FakeDeviceBindingRepository(allowed: false),
      );

      final state = await container.read(sessionProvider.future);

      expect(state, isA<SessionUnauthorizedDevice>());
    },
  );

  test('Device Binding error becomes controlled SessionError', () async {
    final container = await createContainer(
      currentUser: approvedUser,
      claims: approvedClaims,
      deviceRepository: FakeDeviceBindingRepository(
        error: StateError('device service unavailable'),
      ),
    );

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SessionError>());
    expect((state as SessionError).error, isA<StateError>());
  });

  test(
    'authenticated session bootstraps again after provider recreation',
    () async {
      final firstContainer = await createContainer(
        currentUser: approvedUser,
        claims: approvedClaims,
        deviceRepository: FakeDeviceBindingRepository(allowed: true),
      );
      final firstState = await firstContainer.read(sessionProvider.future);

      final secondContainer = await createContainer(
        currentUser: approvedUser,
        claims: approvedClaims,
        deviceRepository: FakeDeviceBindingRepository(allowed: true),
      );
      final secondState = await secondContainer.read(sessionProvider.future);

      expect(firstState, isA<SessionAuthenticated>());
      expect(secondState, isA<SessionAuthenticated>());
    },
  );

  test('invalid current user resolves to unauthenticated session', () async {
    final container = await createContainer(
      currentUser: null,
      claims: const <String, dynamic>{},
      deviceRepository: FakeDeviceBindingRepository(allowed: true),
    );

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SessionUnauthenticated>());
  });

  test(
    'logout delegates to AuthRepository and invalidates session bootstrap',
    () async {
      final authRepository = FakeAuthRepository(currentUser: approvedUser);
      final claimsController = StreamController<Map<String, dynamic>?>();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          customClaimsProvider.overrideWith((ref) {
            final claimsController = StreamController<Map<String, dynamic>?>(sync: true);
            claimsController.add(approvedClaims);
            ref.onDispose(() => claimsController.close());
            return claimsController.stream;
          }),
          deviceBindingRepositoryProvider.overrideWithValue(
            FakeDeviceBindingRepository(allowed: true),
          ),
        ],
      );
      addTearDown(() {
        claimsController.close();
        container.dispose();
      });

      // Keep the session graph alive exactly like the live AuthGate does.
      container.listen(sessionProvider, (_, _) {});

      expect(
        await container.read(sessionProvider.future),
        isA<SessionAuthenticated>(),
      );

      await container.read(sessionProvider.notifier).logout();
      final stateAfterLogout = await container.read(sessionProvider.future);

      expect(authRepository.logoutCalls, 1);
      expect(stateAfterLogout, isA<SessionUnauthenticated>());
    },
  );

  test(
    'new claims are reflected after session bootstrap invalidation',
    () async {
      final claimsController = StreamController<Map<String, dynamic>?>(sync: true);
      claimsController.add(const {'approved': false});
      final authRepository = FakeAuthRepository(currentUser: approvedUser);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          customClaimsProvider.overrideWith((ref) {
            // Keep the external claimsController for the dynamic test, but make it sync: true
            ref.onDispose(() => claimsController.close());
            return claimsController.stream;
          }),
          deviceBindingRepositoryProvider.overrideWithValue(
            FakeDeviceBindingRepository(allowed: true),
          ),
        ],
      );
      addTearDown(() {
        claimsController.close();
        container.dispose();
      });

      // Keep the session graph alive exactly like the live AuthGate does.
      container.listen(sessionProvider, (_, _) {});

      final initialState = await container.read(sessionProvider.future);
      expect(initialState, isA<SessionPendingApproval>());

      claimsController.add(approvedClaims);
      await Future<void>.delayed(Duration.zero);
      container.invalidate(sessionProvider);
      final refreshedState = await container.read(sessionProvider.future);

      expect(refreshedState, isA<SessionAuthenticated>());
    },
  );

  test('claims change is reflected by the pure authorization resolver', () {
    final oldClaims = <String, dynamic>{'approved': false};
    final newClaims = <String, dynamic>{'approved': true};

    expect(
      resolveAccountSessionState(user: approvedUser, claims: oldClaims),
      isA<SessionPendingApproval>(),
    );
    expect(
      resolveAccountSessionState(user: approvedUser, claims: newClaims),
      isNull,
    );
  });
}

class FakeAuthRepository implements AuthRepository {
  AuthUser? currentUser;
  int logoutCalls = 0;

  FakeAuthRepository({required this.currentUser});

  @override
  Future<AuthUser?> getCurrentUser() async => currentUser;

  @override
  Future<void> logout() async {
    logoutCalls++;
    currentUser = null;
  }

  @override
  Future<AuthUser> login({
    required String phoneNumber,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> register({
    required String fullName,
    required String phoneNumber,
    String? profilePhoto,
    required String grade,
    String? customGroupId,
    String? customGroupName,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<StaffDirectoryEntryEntity>> listStaffDirectory() {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> staffLogin({
    required String displayName,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

class FakeDeviceBindingRepository implements DeviceBindingRepository {
  final bool? allowed;
  final Object? error;

  FakeDeviceBindingRepository({this.allowed, this.error});

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    if (error != null) throw error!;
    return const DeviceInfo(
      deviceId: 'device-1',
      deviceName: 'Test Device',
      platform: 'test',
      osVersion: '1.0',
      appVersion: '1.0.0',
    );
  }

  @override
  Future<bool> validateDevice({
    required String userId,
    required DeviceInfo deviceInfo,
  }) async {
    if (error != null) throw error!;
    return allowed ?? false;
  }
}
