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

  Future<String> _getPersistentDeviceId() async {
    const key = 'device_id_uuidv4';
    String? id = await secureStorage.read(key: key);
    if (id == null) {
      id = const Uuid().v4();
      await secureStorage.write(key: key, value: id);
    }
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
