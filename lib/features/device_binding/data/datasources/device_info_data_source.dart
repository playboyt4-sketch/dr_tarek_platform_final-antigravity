import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/device_info.dart';

class DeviceInfoDataSource {
  final DeviceInfoPlugin deviceInfoPlugin;
  final FlutterSecureStorage secureStorage;

  const DeviceInfoDataSource({
    required this.deviceInfoPlugin,
    this.secureStorage = const FlutterSecureStorage(),
  });

  /// Canonical persistent binding id (`device_id_uuidv4` — the same id
  /// registered server-side via `onLoginAttempt`). It is mirrored under
  /// the legacy `device_binding_device_id` key so readers that still use
  /// the old key (FCM push registration) resolve the identical id instead
  /// of null. Both keys always carry the same value.
  static const _primaryDeviceIdKey = 'device_id_uuidv4';
  static const _legacyDeviceIdKey = 'device_binding_device_id';

  Future<String> _getPersistentDeviceId() async {
    String? id = await secureStorage.read(key: _primaryDeviceIdKey);
    if (id == null || id.isEmpty) {
      id = await secureStorage.read(key: _legacyDeviceIdKey);
    }
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
    }
    await secureStorage.write(key: _primaryDeviceIdKey, value: id);
    await secureStorage.write(key: _legacyDeviceIdKey, value: id);
    return id;
  }

  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceId = await _getPersistentDeviceId();

    if (kIsWeb) {
      return DeviceInfo(
        deviceId: deviceId,
        deviceName: 'Web Browser',
        platform: 'web',
        osVersion: 'session',
        appVersion: packageInfo.version,
      );
    }

    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;

      return DeviceInfo(
        deviceId: deviceId,
        deviceName: '${info.manufacturer} ${info.model}',
        platform: 'android',
        osVersion: info.version.release,
        appVersion: packageInfo.version,
      );
    }

    if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;

      return DeviceInfo(
        deviceId: deviceId,
        deviceName: info.name,
        platform: 'ios',
        osVersion: info.systemVersion,
        appVersion: packageInfo.version,
      );
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceName: 'Unsupported Device',
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      appVersion: packageInfo.version,
    );
  }
}
