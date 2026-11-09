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
  /// Coalesces concurrent validations for the same user. Two bootstraps can
  /// fire a few milliseconds apart; without this, both calls race inside
  /// `registerKnownDevice` and can create duplicate registry rows.
  String? _validationUserId;
  Future<void>? _validationInFlight;

  @override
  Future<bool> build() async {
    // validateDevice() is invoked imperatively from the session bootstrap;
    // the element must survive between the notifier read and the state write.
    ref.keepAlive();

    return false;
  }

  Future<void> validateDevice({required String userId}) {
    final inFlight = _validationInFlight;
    if (inFlight != null && _validationUserId == userId) {
      return inFlight;
    }

    final future = _runValidation(userId);
    _validationUserId = userId;
    _validationInFlight = future;

    return future.whenComplete(() {
      if (identical(_validationInFlight, future)) {
        _validationInFlight = null;
        _validationUserId = null;
      }
    });
  }

  Future<void> _runValidation(String userId) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(deviceBindingRepositoryProvider);
      final deviceInfo = await repository.getDeviceInfo();

      return repository.validateDevice(userId: userId, deviceInfo: deviceInfo);
    });
  }
}
