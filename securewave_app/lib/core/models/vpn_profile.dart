class VpnProfile {
  const VpnProfile({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.protocol,
    required this.serverId,
    required this.serverLocation,
    required this.issuedAt,
    required this.expiresAt,
    required this.wireguardConfig,
    required this.profile,
    required this.dnsServers,
    required this.adMalwareBlocking,
    required this.dnsEnforcement,
    required this.killSwitchMode,
    required this.killSwitchEnforcement,
    required this.peerRegistered,
    required this.registrationStatus,
  });

  final int deviceId;
  final String? deviceName;
  final String? deviceType;
  final String protocol;
  final String serverId;
  final String serverLocation;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final String? wireguardConfig;
  final Map<String, dynamic>? profile;

  final List<String> dnsServers;
  final String adMalwareBlocking;
  final String dnsEnforcement;

  final String killSwitchMode;
  final String killSwitchEnforcement;

  final bool peerRegistered;
  final String? registrationStatus;

  factory VpnProfile.fromJson(Map<String, dynamic> json) {
    final dns = json['dns'] is Map ? Map<String, dynamic>.from(json['dns'] as Map) : const <String, dynamic>{};
    final killSwitch =
        json['kill_switch'] is Map ? Map<String, dynamic>.from(json['kill_switch'] as Map) : const <String, dynamic>{};
    final rawProfile = json['profile'];
    final profile = rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null;

    final dnsServersRaw = dns['servers'];
    final dnsServers = dnsServersRaw is List
        ? dnsServersRaw.whereType<Object>().map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    return VpnProfile(
      deviceId: json['device_id'] is int ? json['device_id'] as int : int.tryParse(json['device_id']?.toString() ?? '') ?? 0,
      deviceName: json['device_name']?.toString(),
      deviceType: json['device_type']?.toString(),
      protocol: json['protocol']?.toString() ?? 'wireguard',
      serverId: json['server_id']?.toString() ?? '',
      serverLocation: json['server_location']?.toString() ?? '',
      issuedAt: json['issued_at'] != null ? DateTime.tryParse(json['issued_at'].toString()) : null,
      expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at'].toString()) : null,
      wireguardConfig: json['wireguard_config']?.toString(),
      profile: profile,
      dnsServers: dnsServers,
      adMalwareBlocking: dns['ad_malware_blocking']?.toString() ?? 'on',
      dnsEnforcement: dns['enforcement']?.toString() ?? 'best_effort',
      killSwitchMode: killSwitch['mode']?.toString() ?? 'enabled',
      killSwitchEnforcement: killSwitch['enforcement']?.toString() ?? 'best_effort',
      peerRegistered: json['peer_registered'] == true,
      registrationStatus: json['registration_status']?.toString(),
    );
  }

  Map<String, dynamic> toNativeProfile() {
    if (profile != null && profile!.isNotEmpty) return profile!;
    final wg = (wireguardConfig ?? '').trim();
    if (wg.isNotEmpty) {
      return <String, dynamic>{
        'type': 'wireguard',
        'wireguard_config': wg,
      };
    }
    return const <String, dynamic>{};
  }
}
