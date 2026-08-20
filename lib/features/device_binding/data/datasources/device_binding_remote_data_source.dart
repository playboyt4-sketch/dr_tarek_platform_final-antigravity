import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/device_info.dart';

class DeviceBindingRemoteDataSource {
  final FirebaseFunctions functions;

  const DeviceBindingRemoteDataSource({required this.functions});

  Future<bool> validateDevice({
    required String userId,
    required DeviceInfo deviceInfo,
  }) async {
    final callable = functions.httpsCallable('onLoginAttempt');

    final result = await callable.call({
      'userId': userId,
      'deviceId': deviceInfo.deviceId,
      'deviceName': deviceInfo.deviceName,
      'platform': deviceInfo.platform,
      'osVersion': deviceInfo.osVersion,
      'appVersion': deviceInfo.appVersion,
    });

    final data = Map<String, dynamic>.from(result.data as Map);

    return data['allowed'] == true;
  }
}
