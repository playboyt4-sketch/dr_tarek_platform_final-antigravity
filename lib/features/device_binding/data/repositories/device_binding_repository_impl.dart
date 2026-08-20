import '../../domain/entities/device_info.dart';
import '../../domain/repositories/device_binding_repository.dart';
import '../datasources/device_binding_remote_data_source.dart';
import '../datasources/device_info_data_source.dart';

class DeviceBindingRepositoryImpl implements DeviceBindingRepository {
  final DeviceInfoDataSource deviceInfoDataSource;
  final DeviceBindingRemoteDataSource remoteDataSource;

  const DeviceBindingRepositoryImpl({
    required this.deviceInfoDataSource,
    required this.remoteDataSource,
  });

  @override
  Future<DeviceInfo> getDeviceInfo() {
    return deviceInfoDataSource.getDeviceInfo();
  }

  @override
  Future<bool> validateDevice({
    required String userId,
    required DeviceInfo deviceInfo,
  }) {
    return remoteDataSource.validateDevice(
      userId: userId,
      deviceInfo: deviceInfo,
    );
  }
}
