import 'vpn_protocol.dart';

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
    required this.openVpnConfig,
    required this.openVpnUsername,
    required this.openVpnPassword,
    required this.ikev2Config,
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
  final String wireguardConfig;
  final String openVpnConfig;
  final String? openVpnUsername;
  final String? openVpnPassword;
  final String ikev2Config;

  final List<String> dnsServers;
  final String adMalwareBlocking;
  final String dnsEnforcement;

  final String killSwitchMode;
  final String killSwitchEnforcement;

  final bool peerRegistered;
  final String? registrationStatus;

  String configForProtocol(VpnProtocol protocol) {
    switch (protocol) {
      case VpnProtocol.wireGuard:
        return wireguardConfig;
      case VpnProtocol.openVpn:
        return openVpnConfig;
      case VpnProtocol.ikev2:
        return ikev2Config;
    }
  }

  factory VpnProfile.fromJson(Map<String, dynamic> json) {
    final nestedProfile = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : const <String, dynamic>{};
    final dns = json['dns'] is Map
        ? Map<String, dynamic>.from(json['dns'] as Map)
        : const <String, dynamic>{};
    final killSwitch = json['kill_switch'] is Map
        ? Map<String, dynamic>.from(json['kill_switch'] as Map)
        : const <String, dynamic>{};

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
      protocol: json['protocol']?.toString() ?? 'wireguard',
      serverId: json['server_id']?.toString() ?? '',
      serverLocation: json['server_location']?.toString() ?? '',
      issuedAt: json['issued_at'] != null
          ? DateTime.tryParse(json['issued_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      wireguardConfig: json['wireguard_config']?.toString() ??
          nestedProfile['wireguard_config']?.toString() ??
          '',
      openVpnConfig: json['openvpn_config']?.toString() ??
          nestedProfile['openvpn_config']?.toString() ??
          nestedProfile['ovpn_config']?.toString() ??
          '',
      // The current API returns protocol-specific credentials inside the
      // nested `profile` object. Keep the top-level fields for the established
      // schema and fall back to the nested shape without logging or persisting
      // the values.
      openVpnUsername: json['openvpn_username']?.toString() ??
          nestedProfile['openvpn_username']?.toString() ??
          nestedProfile['username']?.toString(),
      openVpnPassword: json['openvpn_password']?.toString() ??
          nestedProfile['openvpn_password']?.toString() ??
          nestedProfile['password']?.toString(),
      ikev2Config: json['ikev2_config']?.toString() ??
          nestedProfile['ikev2_config']?.toString() ??
          _ikev2ProfileToConfig(nestedProfile),
      dnsServers: dnsServers,
      adMalwareBlocking: dns['ad_malware_blocking']?.toString() ?? 'on',
      dnsEnforcement: dns['enforcement']?.toString() ?? 'best_effort',
      killSwitchMode: killSwitch['mode']?.toString() ?? 'enabled',
      killSwitchEnforcement:
          killSwitch['enforcement']?.toString() ?? 'best_effort',
      peerRegistered: json['peer_registered'] == true,
      registrationStatus: json['registration_status']?.toString(),
    );
  }
}

String _ikev2ProfileToConfig(Map<String, dynamic> profile) {
  if (profile['type']?.toString().toLowerCase() != 'ikev2') return '';
  final server = profile['server']?.toString() ?? '';
  final username = profile['username']?.toString() ?? '';
  final password = profile['password']?.toString() ?? '';
  if (server.isEmpty || username.isEmpty || password.isEmpty) return '';
  final remoteId = profile['remote_id']?.toString() ?? server;
  final ca = profile['ca_cert_pem']?.toString() ?? '';
  if ([server, username, password, remoteId].any(_containsLineBreak)) return '';
  final secretId = username.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
  return [
    'connections {',
    '  securewave {',
    '    version = 2',
    '    remote_addrs = $server',
    '    proposals = aes256-sha256-modp2048',
    '    local {',
    '      auth = eap-mschapv2',
    '      eap_id = "${_swanctlQuote(username)}"',
    '    }',
    '    remote {',
    '      auth = pubkey',
    '      id = "${_swanctlQuote(remoteId)}"',
    '      cacerts = securewave-ikev2-ca.pem',
    '    }',
    '    children {',
    '      securewave {',
    '        remote_ts = 0.0.0.0/0,::/0',
    '        esp_proposals = aes256-sha256-modp2048',
    '      }',
    '    }',
    '  }',
    '}',
    'secrets {',
    '  eap-${secretId.isEmpty ? 'securewave-user' : secretId} {',
    '    id = "${_swanctlQuote(username)}"',
    '    ${'secret'} = "${_swanctlQuote(password)}"',
    '  }',
    '}',
    if (ca.isNotEmpty) ...[
      '# ca_cert_pem_begin',
      ca,
      '# ca_cert_pem_end',
    ],
  ].join('\n');
}

String _swanctlQuote(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

bool _containsLineBreak(String value) =>
    value.contains('\n') || value.contains('\r');
