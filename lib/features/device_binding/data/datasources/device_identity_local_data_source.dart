import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdentityLocalDataSource {
  static const _deviceIdKey = 'device_binding_device_id';

  final FlutterSecureStorage storage;

  const DeviceIdentityLocalDataSource({required this.storage});

  Future<String?> readDeviceId() {
    return storage.read(key: _deviceIdKey);
  }

  Future<void> saveDeviceId(String deviceId) {
    return storage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<void> deleteDeviceId() {
    return storage.delete(key: _deviceIdKey);
  }
}
