import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/device_binding_remote_data_source.dart';
import '../../data/datasources/device_info_data_source.dart';
import '../../data/repositories/device_binding_repository_impl.dart';
import '../../domain/entities/device_info.dart';
import '../../domain/repositories/device_binding_repository.dart';

final deviceBindingRepositoryProvider = Provider<DeviceBindingRepository>((
  ref,
) {
  final deviceInfoDataSource = DeviceInfoDataSource(
    deviceInfoPlugin: DeviceInfoPlugin(),
  );

  final remoteDataSource = DeviceBindingRemoteDataSource(
    functions: FirebaseFunctions.instance,
  );

  return DeviceBindingRepositoryImpl(
    deviceInfoDataSource: deviceInfoDataSource,
    remoteDataSource: remoteDataSource,
  );
});

final deviceInfoProvider = FutureProvider<DeviceInfo>((ref) {
  return ref.watch(deviceBindingRepositoryProvider).getDeviceInfo();
});

final deviceBindingProvider =
    AsyncNotifierProvider<DeviceBindingController, bool>(
      DeviceBindingController.new,
    );

class DeviceBindingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return false;
  }

  Future<void> validateDevice({required String userId}) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(deviceBindingRepositoryProvider);
      final deviceInfo = await repository.getDeviceInfo();

      return repository.validateDevice(userId: userId, deviceInfo: deviceInfo);
    });
  }
}
