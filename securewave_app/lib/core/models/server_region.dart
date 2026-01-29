class ServerRegion {
  const ServerRegion({
    required this.id,
    required this.name,
    this.city,
    this.country,
    this.latencyMs,
  });

  final String id;
  final String name;
  final String? city;
  final String? country;
  final int? latencyMs;

  factory ServerRegion.fromJson(Map<String, dynamic> json) {
    return ServerRegion(
      id: json['server_id']?.toString() ??
          json['id']?.toString() ??
          json['location']?.toString() ??
          json['name']?.toString() ??
          '',
      name: json['location']?.toString() ?? json['name']?.toString() ?? 'Unknown region',
      city: json['city']?.toString(),
      country: json['country']?.toString(),
      latencyMs: json['latency_ms'] is int ? json['latency_ms'] as int : null,
    );
  }
}
