import 'vpn_protocol.dart';

class VpnProtocolCatalogEntry {
  const VpnProtocolCatalogEntry({
    required this.protocol,
    required this.enabled,
    required this.serverEnabled,
    required this.planEnabled,
    required this.platformSupported,
    required this.reason,
  });

  final VpnProtocol protocol;
  final bool enabled;
  final bool serverEnabled;
  final bool planEnabled;
  final bool platformSupported;
  final String? reason;

  factory VpnProtocolCatalogEntry.fromJson(Map<String, dynamic> json) {
    bool b(String key) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value?.toString().toLowerCase() == 'true';
    }

    return VpnProtocolCatalogEntry(
      protocol: vpnProtocolFromStorage(json['protocol']?.toString()),
      enabled: b('enabled'),
      serverEnabled: b('server_enabled'),
      planEnabled: b('plan_enabled'),
      platformSupported: b('platform_supported'),
      reason: json['reason']?.toString(),
    );
  }
}

class VpnProtocolCatalog {
  const VpnProtocolCatalog({
    required this.userTier,
    required this.deviceType,
    required this.protocols,
  });

  final String userTier;
  final String? deviceType;
  final List<VpnProtocolCatalogEntry> protocols;

  factory VpnProtocolCatalog.fromJson(Map<String, dynamic> json) {
    final rawProtocols = json['protocols'];
    final protocols = rawProtocols is List
        ? rawProtocols
            .whereType<Map>()
            .map((item) => VpnProtocolCatalogEntry.fromJson(
                Map<String, dynamic>.from(item)))
            .toList()
        : <VpnProtocolCatalogEntry>[];
    return VpnProtocolCatalog(
      userTier: json['user_tier']?.toString() ?? 'free',
      deviceType: json['device_type']?.toString(),
      protocols: protocols,
    );
  }

  Set<VpnProtocol> enabledProtocols() {
    final out = <VpnProtocol>{};
    for (final item in protocols) {
      if (item.enabled && item.protocol != VpnProtocol.auto) {
        out.add(item.protocol);
      }
    }
    return out;
  }
}
