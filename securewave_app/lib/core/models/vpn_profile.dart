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
    String? stringOrNull(Object? value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    String? normalizeMultiline(Object? value) {
      final text = stringOrNull(value);
      if (text == null) return null;
      var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (!normalized.contains('\n') && normalized.contains(r'\n')) {
        normalized = normalized.replaceAll(r'\n', '\n');
      }
      return normalized.trim();
    }

    bool boolLike(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value?.toString().trim().toLowerCase();
      return text == 'true' || text == '1' || text == 'yes';
    }

    final dns = json['dns'] is Map
        ? Map<String, dynamic>.from(json['dns'] as Map)
        : const <String, dynamic>{};
    final killSwitch = json['kill_switch'] is Map
        ? Map<String, dynamic>.from(json['kill_switch'] as Map)
        : const <String, dynamic>{};
    final rawProfile = json['profile'];
    Map<String, dynamic>? profile =
        rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null;
    final profileType = stringOrNull(profile?['type'])?.toLowerCase();
    final wireguardConfig = normalizeMultiline(
      json['wireguard_config'] ??
          profile?['wireguard_config'] ??
          profile?['config'],
    );
    final topLevelOpenVpnConfig = normalizeMultiline(
      json['ovpn_config'] ??
          json['openvpn_config'] ??
          profile?['ovpn_config'] ??
          profile?['openvpn_config'] ??
          profile?['config'],
    );
    final topLevelIkev2Server =
        stringOrNull(json['server'] ?? profile?['server']);
    var protocol = stringOrNull(json['protocol'])?.toLowerCase() ??
        profileType ??
        'wireguard';
    if (protocol != 'wireguard' &&
        protocol != 'openvpn' &&
        protocol != 'ikev2') {
      if ((wireguardConfig ?? '').isNotEmpty) {
        protocol = 'wireguard';
      } else if ((topLevelOpenVpnConfig ?? '').isNotEmpty) {
        protocol = 'openvpn';
      } else if ((topLevelIkev2Server ?? '').isNotEmpty) {
        protocol = 'ikev2';
      } else {
        protocol = 'wireguard';
      }
    }

    if (profile == null || profile.isEmpty) {
      if (protocol == 'wireguard' &&
          (wireguardConfig ?? '').trim().isNotEmpty) {
        profile = <String, dynamic>{
          'type': 'wireguard',
          'wireguard_config': wireguardConfig!.trim(),
        };
      } else if (protocol == 'openvpn' &&
          (topLevelOpenVpnConfig ?? '').isNotEmpty) {
        profile = <String, dynamic>{
          'type': 'openvpn',
          'ovpn_config': topLevelOpenVpnConfig,
          if ((json['auth_method']?.toString().trim() ?? '').isNotEmpty)
            'auth_method': json['auth_method'],
          if ((json['username']?.toString().trim() ?? '').isNotEmpty)
            'username': json['username'],
          if ((json['password']?.toString().trim() ?? '').isNotEmpty)
            'password': json['password'],
        };
      } else if (protocol == 'ikev2' &&
          (topLevelIkev2Server ?? '').isNotEmpty) {
        profile = <String, dynamic>{
          'type': 'ikev2',
          'server': topLevelIkev2Server,
          if ((json['auth_method']?.toString().trim() ?? '').isNotEmpty)
            'auth_method': json['auth_method'],
          if ((json['remote_id']?.toString().trim() ?? '').isNotEmpty)
            'remote_id': json['remote_id'],
          if ((json['username']?.toString().trim() ?? '').isNotEmpty)
            'username': json['username'],
          if ((json['password']?.toString().trim() ?? '').isNotEmpty)
            'password': json['password'],
          if ((json['ca_cert_pem']?.toString().trim() ?? '').isNotEmpty)
            'ca_cert_pem': json['ca_cert_pem'],
          if ((json['client_pkcs12_base64']?.toString().trim() ?? '')
              .isNotEmpty)
            'client_pkcs12_base64': json['client_pkcs12_base64'],
          if ((json['client_pkcs12_password']?.toString().trim() ?? '')
              .isNotEmpty)
            'client_pkcs12_password': json['client_pkcs12_password'],
        };
      }
    } else {
      profile['type'] =
          stringOrNull(profile['type'])?.toLowerCase() ?? protocol;
      if (protocol == 'wireguard' && (wireguardConfig ?? '').isNotEmpty) {
        profile['wireguard_config'] = wireguardConfig;
      }
      if (protocol == 'openvpn' && (topLevelOpenVpnConfig ?? '').isNotEmpty) {
        profile['ovpn_config'] = topLevelOpenVpnConfig;
      }
      if (protocol == 'ikev2' && (topLevelIkev2Server ?? '').isNotEmpty) {
        profile['server'] = topLevelIkev2Server;
      }
    }

    final dnsServersRaw = dns['servers'];
    final dnsServers = dnsServersRaw is List
        ? dnsServersRaw
            .whereType<Object>()
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    return VpnProfile(
      deviceId: json['device_id'] is int
          ? json['device_id'] as int
          : int.tryParse(json['device_id']?.toString() ?? '') ?? 0,
      deviceName: json['device_name']?.toString(),
      deviceType: json['device_type']?.toString(),
      protocol: protocol,
      serverId: json['server_id']?.toString() ?? '',
      serverLocation: json['server_location']?.toString() ?? '',
      issuedAt: json['issued_at'] != null
          ? DateTime.tryParse(json['issued_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      wireguardConfig: wireguardConfig,
      profile: profile,
      dnsServers: dnsServers,
      adMalwareBlocking: dns['ad_malware_blocking']?.toString() ?? 'on',
      dnsEnforcement: dns['enforcement']?.toString() ?? 'best_effort',
      killSwitchMode: killSwitch['mode']?.toString() ?? 'enabled',
      killSwitchEnforcement:
          killSwitch['enforcement']?.toString() ?? 'best_effort',
      peerRegistered: boolLike(json['peer_registered']),
      registrationStatus: json['registration_status']?.toString(),
    );
  }

  Map<String, dynamic> toNativeProfile() {
    if (profile != null && profile!.isNotEmpty) {
      return <String, dynamic>{
        ...profile!,
        if (serverId.trim().isNotEmpty) 'server_id': serverId,
        if (serverLocation.trim().isNotEmpty) 'server_location': serverLocation,
        if (protocol.trim().isNotEmpty) 'protocol': protocol,
        if (deviceId > 0) 'device_id': deviceId,
      };
    }
    final wg = (wireguardConfig ?? '').trim();
    if (wg.isNotEmpty) {
      return <String, dynamic>{
        'type': 'wireguard',
        'wireguard_config': wg,
        if (serverId.trim().isNotEmpty) 'server_id': serverId,
        if (serverLocation.trim().isNotEmpty) 'server_location': serverLocation,
        'protocol': protocol,
        if (deviceId > 0) 'device_id': deviceId,
      };
    }
    return const <String, dynamic>{};
  }
}
