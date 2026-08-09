import 'vpn_protocol.dart';

class ServerRegion {
  const ServerRegion({
    required this.id,
    required this.name,
    this.location,
    this.city,
    this.country,
    this.latencyMs,
    this.loadPercent,
    this.health,
    this.supportedProtocols = const <String>[],
  });

  final String id;
  final String name;
  final String? location;
  final String? city;
  final String? country;
  final int? latencyMs;
  final double? loadPercent;
  final String? health;
  final List<String> supportedProtocols;

  bool hasProtocolEvidenceFor(VpnProtocol protocol) {
    final value = vpnProtocolStorageValue(protocol);
    return supportedProtocols.any(
      (item) => item.trim().toLowerCase() == value,
    );
  }

  bool get isUnavailable {
    final value = health?.trim().toLowerCase();
    return value == 'offline' ||
        value == 'unhealthy' ||
        value == 'unavailable' ||
        value == 'error';
  }

  bool get isWireGuardConnectable =>
      hasProtocolEvidenceFor(VpnProtocol.wireGuard) && !isUnavailable;

  factory ServerRegion.fromJson(Map<String, dynamic> json) {
    final rawProtocols = json['supported_protocols'];
    final protocols = <String>[];
    if (rawProtocols is List) {
      protocols.addAll(
        rawProtocols
            .whereType<Object>()
            .map((item) => item.toString().trim().toLowerCase())
            .where((item) => item == 'wireguard'),
      );
    }
    final protocol = json['protocol']?.toString().trim().toLowerCase();
    if (protocol == 'wireguard' && !protocols.contains(protocol)) {
      protocols.add(protocol!);
    }
    if (json['supports_wireguard'] == true &&
        !protocols.contains('wireguard')) {
      protocols.add('wireguard');
    }

    final latency = json['latency_ms'];
    final load = json['load_percent'];
    final location = _optionalString(json['location']);
    return ServerRegion(
      id: _optionalString(json['server_id']) ??
          _optionalString(json['id']) ??
          '',
      name: _optionalString(json['name']) ?? location ?? 'SecureWave Beta',
      location: location,
      city: _optionalString(json['city']),
      country: _optionalString(json['country']),
      latencyMs: latency is num ? latency.round() : null,
      loadPercent: load is num && load.isFinite ? load.toDouble() : null,
      health: _optionalString(json['health']) ??
          _optionalString(json['health_status']) ??
          _optionalString(json['region_health_status']),
      supportedProtocols: List.unmodifiable(protocols),
    );
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
