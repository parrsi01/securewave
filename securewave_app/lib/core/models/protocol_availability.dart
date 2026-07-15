import 'vpn_protocol.dart';

class ProtocolAvailability {
  const ProtocolAvailability({
    required this.protocol,
    required this.enabled,
    required this.serverEnabled,
    required this.platformSupported,
    this.reason,
  });

  final VpnProtocol protocol;
  final bool enabled;
  final bool serverEnabled;
  final bool platformSupported;
  final String? reason;

  factory ProtocolAvailability.fromJson(Map<String, dynamic> json) {
    return ProtocolAvailability(
      protocol: vpnProtocolFromStorage(json['protocol']?.toString()),
      enabled: json['enabled'] == true,
      serverEnabled: json['server_enabled'] == true,
      platformSupported: json['platform_supported'] == true,
      reason: json['reason']?.toString(),
    );
  }
}
