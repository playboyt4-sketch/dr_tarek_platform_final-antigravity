class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? osVersion;
  final String appVersion;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
  });
}
