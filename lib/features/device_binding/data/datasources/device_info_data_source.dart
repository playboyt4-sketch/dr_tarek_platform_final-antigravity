import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/entities/device_info.dart';

class DeviceInfoDataSource {
  final DeviceInfoPlugin deviceInfoPlugin;

  const DeviceInfoDataSource({required this.deviceInfoPlugin});

  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (Platform.isAndroid) {
      final info = await deviceInfoPlugin.androidInfo;

      return DeviceInfo(
        deviceId: info.id,
        deviceName: '${info.manufacturer} ${info.model}',
        platform: 'android',
        osVersion: info.version.release,
        appVersion: packageInfo.version,
      );
    }

    if (Platform.isIOS) {
      final info = await deviceInfoPlugin.iosInfo;

      return DeviceInfo(
        deviceId: info.identifierForVendor ?? info.utsname.machine,
        deviceName: info.name,
        platform: 'ios',
        osVersion: info.systemVersion,
        appVersion: packageInfo.version,
      );
    }

    return DeviceInfo(
      deviceId: 'unsupported',
      deviceName: 'Unsupported Device',
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      appVersion: packageInfo.version,
    );
  }
}
