class ServerRegion {
  const ServerRegion({
    required this.id,
    required this.name,
    this.city,
    this.country,
    this.latencyMs,
    this.status,
    this.healthStatus,
    this.regionHealthStatus,
    this.loadPercent,
    this.supportedProtocols = const [],
    this.premiumOnly = false,
  });

  final String id;
  final String name;
  final String? city;
  final String? country;
  final int? latencyMs;
  final String? status;
  final String? healthStatus;
  final String? regionHealthStatus;
  final double? loadPercent;
  final List<String> supportedProtocols;
  final bool premiumOnly;

  bool supportsProtocol(String protocol) {
    return supportedProtocols
        .map((item) => item.toLowerCase().trim())
        .contains(protocol.toLowerCase().trim());
  }

  factory ServerRegion.fromJson(Map<String, dynamic> json) {
    final protocolsRaw = json['supported_protocols'];
    final protocols = <String>[];
    if (protocolsRaw is List) {
      protocols.addAll(
        protocolsRaw
            .whereType<Object>()
            .map((item) => item.toString().trim().toLowerCase())
            .where((item) => item.isNotEmpty),
      );
    }
    final latencyRaw = json['latency_ms'];
    final loadRaw = json['load_percent'];

    return ServerRegion(
      id:
          json['server_id']?.toString() ??
          json['id']?.toString() ??
          json['location']?.toString() ??
          json['name']?.toString() ??
          '',
      name:
          json['location']?.toString() ??
          json['name']?.toString() ??
          'Unknown region',
      city: json['city']?.toString(),
      country: json['country']?.toString(),
      latencyMs: latencyRaw is num ? latencyRaw.round() : null,
      status: json['status']?.toString(),
      healthStatus: json['health_status']?.toString(),
      regionHealthStatus: json['region_health_status']?.toString(),
      loadPercent: loadRaw is num ? loadRaw.toDouble() : null,
      supportedProtocols: protocols,
      premiumOnly: json['premium_only'] == true,
    );
  }
}
