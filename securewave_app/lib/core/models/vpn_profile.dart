class VpnProfile {
  const VpnProfile({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.serverId,
    required this.serverLocation,
    required this.wireguardConfig,
  });

  final int deviceId;
  final String deviceName;
  final String deviceType;
  final String serverId;
  final String serverLocation;
  final String wireguardConfig;

  factory VpnProfile.fromJson(Map<String, dynamic> json) => VpnProfile(
    deviceId: int.tryParse(json['device_id']?.toString() ?? '') ?? 0,
    deviceName: json['device_name']?.toString() ?? 'SecureWave Linux',
    deviceType: json['device_type']?.toString() ?? 'linux',
    serverId: json['server_id']?.toString() ?? '',
    serverLocation: json['server_location']?.toString() ?? 'SecureWave Beta',
    wireguardConfig: json['wireguard_config']?.toString() ?? '',
  );
}
