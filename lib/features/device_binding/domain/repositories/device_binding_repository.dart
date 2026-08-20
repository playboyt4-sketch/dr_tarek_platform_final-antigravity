import '../entities/device_info.dart';

abstract class DeviceBindingRepository {
  Future<DeviceInfo> getDeviceInfo();

  Future<bool> validateDevice({
    required String userId,
    required DeviceInfo deviceInfo,
  });
}
