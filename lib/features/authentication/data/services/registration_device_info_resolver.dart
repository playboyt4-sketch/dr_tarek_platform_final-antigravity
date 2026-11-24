import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/device/device_identity_store.dart';

/// Pre-registration device & push details for new student registration.
///
/// Ensures the initial device record can be seeded with an FCM token
/// so the approval notification reaches the student's device immediately.
class RegistrationDeviceInfo {
  final String? fcmToken;
  final String? deviceId;
  final String? platform;

  const RegistrationDeviceInfo({
    this.fcmToken,
    this.deviceId,
    this.platform,
  });

  static Future<RegistrationDeviceInfo>? _cachedFuture;
  static RegistrationDeviceInfo? _cachedResult;

  static RegistrationDeviceInfo? get cached => _cachedResult;

  /// Starts resolving in the background early during wizard steps.
  static void preWarm({
    FirebaseMessaging? messaging,
    DeviceIdentityStore? deviceIdentityStore,
  }) {
    _cachedFuture ??= resolve(
      messaging: messaging,
      deviceIdentityStore: deviceIdentityStore,
    );
  }

  /// Best-effort resolution of the device identity and FCM token.
  /// Never throws: fails open so registration is never blocked.
  static Future<RegistrationDeviceInfo> resolve({
    FirebaseMessaging? messaging,
    DeviceIdentityStore? deviceIdentityStore,
  }) async {
    if (_cachedResult != null) return _cachedResult!;
    if (_cachedFuture != null && messaging == null && deviceIdentityStore == null) {
      return _cachedFuture!;
    }

    if (kIsWeb) {
      _cachedResult = const RegistrationDeviceInfo(platform: 'web');
      return _cachedResult!;
    }

    try {
      if (Firebase.apps.isEmpty) {
        return const RegistrationDeviceInfo();
      }
    } catch (_) {
      return const RegistrationDeviceInfo();
    }

    String? token;
    String? devId;
    final plat = defaultTargetPlatform == TargetPlatform.android
        ? 'android'
        : (defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : defaultTargetPlatform.name);

    try {
      final fcm = messaging ?? FirebaseMessaging.instance;
      final settings = await fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        if (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) {
          // On iOS, APNs token must be ready before FCM token can be requested.
          for (var i = 0; i < 10; i++) {
            final apns = await fcm.getAPNSToken();
            if (apns != null && apns.isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        token = await fcm.getToken();
      }
    } catch (e) {
      debugPrint('[RegistrationDeviceInfo] FCM token resolution skipped: $e');
    }

    try {
      final store = deviceIdentityStore ?? const DeviceIdentityStore();
      devId = await store.getOrCreate();
    } catch (e) {
      debugPrint('[RegistrationDeviceInfo] DeviceId resolution skipped: $e');
    }

    final result = RegistrationDeviceInfo(
      fcmToken: token,
      deviceId: devId,
      platform: plat,
    );
    _cachedResult = result;
    return result;
  }
}
