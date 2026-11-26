import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dr_tarek_platform/core/security/biometric_lock_service.dart';

class _FakeBiometricClient implements BiometricAuthClient {
  bool canCheck;
  bool supported;
  bool nextAuthResult;
  Object? throwOnCheck;
  Object? throwOnAuth;

  String? lastReason;
  AuthenticationOptions? lastOptions;
  int authCalls = 0;

  _FakeBiometricClient({
    this.canCheck = true,
    this.supported = true,
    this.nextAuthResult = true,
  });

  @override
  Future<bool> get canCheckBiometrics async {
    if (throwOnCheck != null) throw throwOnCheck!;
    return canCheck;
  }

  @override
  Future<bool> isDeviceSupported() async {
    if (throwOnCheck != null) throw throwOnCheck!;
    return supported;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  }) async {
    authCalls++;
    lastReason = localizedReason;
    lastOptions = options;
    if (throwOnAuth != null) throw throwOnAuth!;
    return nextAuthResult;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('BiometricLockService', () {
    test('isBiometricSupported requires both canCheckBiometrics and isDeviceSupported', () async {
      final supportedClient = _FakeBiometricClient(canCheck: true, supported: true);
      final service = BiometricLockService(client: supportedClient, isWeb: false);
      expect(await service.isBiometricSupported(), isTrue);

      final noHardware = _FakeBiometricClient(canCheck: false, supported: true);
      expect(
        await BiometricLockService(client: noHardware, isWeb: false).isBiometricSupported(),
        isFalse,
      );

      final unsupported = _FakeBiometricClient(canCheck: true, supported: false);
      expect(
        await BiometricLockService(client: unsupported, isWeb: false).isBiometricSupported(),
        isFalse,
      );
    });

    test('isBiometricSupported returns false on Web or PlatformException', () async {
      final client = _FakeBiometricClient()
        ..throwOnCheck = PlatformException(code: 'NotAvailable');

      expect(
        await BiometricLockService(client: client, isWeb: false).isBiometricSupported(),
        isFalse,
      );
      expect(
        await BiometricLockService(client: _FakeBiometricClient(), isWeb: true).isBiometricSupported(),
        isFalse,
      );
    });

    test('authenticate uses stickyAuth=true and biometricOnly=false', () async {
      final client = _FakeBiometricClient(nextAuthResult: true);
      final service = BiometricLockService(client: client, isWeb: false);

      final ok = await service.authenticate(localizedReason: 'تأكيد الهوية');
      expect(ok, isTrue);
      expect(client.authCalls, 1);
      expect(client.lastReason, 'تأكيد الهوية');
      expect(client.lastOptions?.stickyAuth, isTrue);
      expect(client.lastOptions?.biometricOnly, isFalse);
    });

    test('authenticate returns false gracefully on PlatformException or Web', () async {
      final throwingClient = _FakeBiometricClient()
        ..throwOnAuth = PlatformException(code: 'AuthFailed');

      expect(
        await BiometricLockService(client: throwingClient, isWeb: false).authenticate(),
        isFalse,
      );
      expect(
        await BiometricLockService(client: _FakeBiometricClient(), isWeb: true).authenticate(),
        isFalse,
      );
    });

    test('preference defaults to false and persists changes in SharedPreferences', () async {
      final service = BiometricLockService(client: _FakeBiometricClient(), isWeb: false);

      expect(await service.isLockEnabled(), isFalse);
      await service.setLockEnabled(true);
      expect(await service.isLockEnabled(), isTrue);
      expect(await loadPersistedBiometricLockEnabled(isWeb: false), isTrue);

      await service.setLockEnabled(false);
      expect(await service.isLockEnabled(), isFalse);
      expect(await loadPersistedBiometricLockEnabled(isWeb: false), isFalse);
    });
  });
}
