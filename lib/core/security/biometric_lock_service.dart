import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key storing the user's opt-in preference for app-level
/// biometric / Face ID locking. Defaults to `false`.
const String kBiometricLockEnabledKey = 'biometric_lock_enabled';

/// Minimal platform adapter around [LocalAuthentication] so unit and widget
/// tests can inject fakes without method-channel setup.
abstract interface class BiometricAuthClient {
  Future<bool> get canCheckBiometrics;
  Future<bool> isDeviceSupported();
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  });
}

class _LocalAuthenticationClient implements BiometricAuthClient {
  final LocalAuthentication _auth;

  _LocalAuthenticationClient([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> get canCheckBiometrics => _auth.canCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  }) =>
      _auth.authenticate(localizedReason: localizedReason, options: options);
}

/// Service responsible for checking biometric capability, running OS biometric
/// (with device-passcode fallback) authentication, and persisting the opt-in flag.
class BiometricLockService {
  final BiometricAuthClient _client;
  final Future<SharedPreferences> Function() _prefsLoader;
  final bool _isWeb;

  BiometricLockService({
    BiometricAuthClient? client,
    Future<SharedPreferences> Function()? prefsLoader,
    bool? isWeb,
  })  : _client = client ?? _LocalAuthenticationClient(),
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _isWeb = isWeb ?? kIsWeb;

  /// Returns `true` only on supported native devices with biometric capability.
  Future<bool> isBiometricSupported() async {
    if (_isWeb) return false;
    try {
      final canCheck = await _client.canCheckBiometrics;
      final deviceSupported = await _client.isDeviceSupported();
      return canCheck && deviceSupported;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts OS biometric authentication with device passcode fallback
  /// (`stickyAuth: true`, `biometricOnly: false`).
  Future<bool> authenticate({
    String localizedReason = 'يرجى تأكيد هويتك لفتح التطبيق',
  }) async {
    if (_isWeb) return false;
    try {
      return await _client.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the persisted opt-in preference (defaults to `false`).
  Future<bool> isLockEnabled() async {
    try {
      final prefs = await _prefsLoader();
      return prefs.getBool(kBiometricLockEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the user's biometric lock preference locally.
  Future<void> setLockEnabled(bool enabled) async {
    final prefs = await _prefsLoader();
    await prefs.setBool(kBiometricLockEnabledKey, enabled);
  }
}

/// Loads the persisted biometric lock preference before `runApp` so cold-start
/// gating knows on frame 1 whether to lock immediately. Never throws.
Future<bool> loadPersistedBiometricLockEnabled({
  Future<SharedPreferences> Function()? prefsLoader,
  bool? isWeb,
}) async {
  if (isWeb ?? kIsWeb) return false;
  try {
    final prefs = await (prefsLoader ?? SharedPreferences.getInstance)();
    return prefs.getBool(kBiometricLockEnabledKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Optional preloaded cold-start value overridden in `main.dart`.
/// `null` indicates tests/environments that did not preload before `runApp`.
final initialBiometricLockEnabledProvider = Provider<bool?>((ref) => null);

final biometricLockServiceProvider = Provider<BiometricLockService>(
  (ref) => BiometricLockService(),
);

final biometricSupportedProvider = FutureProvider<bool>((ref) async {
  ref.keepAlive();
  return ref.watch(biometricLockServiceProvider).isBiometricSupported();
});

final biometricLockEnabledProvider =
    NotifierProvider<BiometricLockEnabledNotifier, bool>(
      BiometricLockEnabledNotifier.new,
    );

class BiometricLockEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.keepAlive();
    final preloaded = ref.watch(initialBiometricLockEnabledProvider);
    if (preloaded != null) {
      return preloaded;
    }
    unawaited(_syncFromStorage());
    return false;
  }

  Future<void> _syncFromStorage() async {
    final stored = await ref.read(biometricLockServiceProvider).isLockEnabled();
    if (state != stored) {
      state = stored;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(biometricLockServiceProvider).setLockEnabled(enabled);
    state = enabled;
  }
}

class AppLockState {
  final bool isLoggingOut;
  final int resetEpoch;

  const AppLockState({
    this.isLoggingOut = false,
    this.resetEpoch = 0,
  });

  AppLockState copyWith({
    bool? isLoggingOut,
    int? resetEpoch,
  }) {
    return AppLockState(
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      resetEpoch: resetEpoch ?? this.resetEpoch,
    );
  }
}

final appLockStateProvider =
    NotifierProvider<AppLockStateNotifier, AppLockState>(
      AppLockStateNotifier.new,
    );

class AppLockStateNotifier extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    ref.keepAlive();
    return const AppLockState();
  }

  /// Marks an in-flight logout so [AppLockGate] unlocks immediately and never
  /// activates biometric prompting while signing out.
  void onLogoutStarted() {
    state = AppLockState(
      isLoggingOut: true,
      resetEpoch: state.resetEpoch + 1,
    );
  }

  /// Clears the transient logout flag once sign-out finishes.
  void onLogoutCompleted() {
    state = AppLockState(
      isLoggingOut: false,
      resetEpoch: state.resetEpoch + 1,
    );
  }
}
