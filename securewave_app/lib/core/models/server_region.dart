class ServerRegion {
  const ServerRegion({
    required this.id,
    required this.name,
    this.city,
    this.country,
    this.countryCode,
    this.region,
    this.regionGroup,
    this.latencyMs,
    this.latencyPriority,
    this.healthStatus,
    this.regionHealthStatus,
    this.regionHealthLastCheckedAt,
    this.regionHealthReasonCode,
    this.publicIp,
    this.tierRestriction,
    this.premiumOnly = false,
    this.supportedProtocols = const <String>[],
  });

  final String id;
  final String name;
  final String? city;
  final String? country;
  final String? countryCode;
  final String? region;
  final String? regionGroup;
  final int? latencyMs;
  final int? latencyPriority;
  final String? healthStatus;
  final String? regionHealthStatus;
  final String? regionHealthLastCheckedAt;
  final String? regionHealthReasonCode;
  final String? publicIp;
  final String? tierRestriction;
  final bool premiumOnly;
  final List<String> supportedProtocols;

  bool selectableForPlan(String? planTier) {
    if (!premiumOnly) return true;
    final tier = (planTier ?? '').trim().toLowerCase();
    return tier.isNotEmpty && tier != 'free';
  }

  factory ServerRegion.fromJson(Map<String, dynamic> json) {
    String? s(String key) {
      final value = json[key]?.toString();
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final serverId = s('server_id') ?? s('id') ?? '';
    final city = s('city');
    final countryCode = s('country_code')?.toUpperCase();
    final country = _normalizeCountryName(s('country'), countryCode);
    final location = s('display_name') ?? s('location') ?? s('name');
    final region = s('region');
    final regionGroup = s('region_group');
    final healthStatus = s('health_status');
    final regionHealthStatus = s('region_health_status') ?? s('region_health');
    final regionHealthLastCheckedAt =
        s('region_health_last_checked_at') ?? s('last_checked_at');
    final regionHealthReasonCode =
        s('region_health_reason_code') ?? s('reason_code');
    final publicIp = s('public_ip');
    final tierRestriction = s('tier_restriction');
    final premiumOnlyRaw = json['premium_only'];
    final premiumOnly = premiumOnlyRaw is bool
        ? premiumOnlyRaw
        : premiumOnlyRaw is num
            ? premiumOnlyRaw != 0
            : premiumOnlyRaw?.toString().toLowerCase() == 'true' ||
                (tierRestriction?.toLowerCase() == 'premium');
    final synthesizedName = [
      if (city != null) city,
      if (country != null) country,
    ].join(', ');

    final rawLatency = json['latency_ms'];
    int? latencyMs;
    if (rawLatency is num) {
      latencyMs = rawLatency.round();
    } else {
      latencyMs = int.tryParse(rawLatency?.toString() ?? '');
    }

    final rawPriority = json['latency_priority'];
    int? latencyPriority;
    if (rawPriority is num) {
      latencyPriority = rawPriority.round();
    } else {
      latencyPriority = int.tryParse(rawPriority?.toString() ?? '');
    }

    final protocolSupport = json['protocol_support'];
    final supportedProtocols = <String>[];
    if (protocolSupport is Map) {
      final map = Map<String, dynamic>.from(protocolSupport);
      for (final entry in map.entries) {
        final value = entry.value;
        final enabled = value is bool
            ? value
            : (value is num
                ? value != 0
                : value?.toString().toLowerCase() == 'true');
        if (enabled) supportedProtocols.add(entry.key.toLowerCase());
      }
      supportedProtocols.sort();
    } else {
      final rawList = json['supported_protocols'];
      if (rawList is List) {
        for (final item in rawList) {
          final text = item?.toString().trim().toLowerCase();
          if (text != null && text.isNotEmpty) supportedProtocols.add(text);
        }
      }
    }

    final idFallback =
        location ?? (synthesizedName.isNotEmpty ? synthesizedName : 'unknown');
    final nameFallback = location ??
        (synthesizedName.isNotEmpty
            ? synthesizedName
            : (serverId.isNotEmpty ? serverId : 'Unknown region'));

    return ServerRegion(
      id: serverId.isNotEmpty ? serverId : idFallback,
      name: nameFallback,
      city: city,
      country: country,
      countryCode: countryCode,
      region: region,
      regionGroup: regionGroup,
      latencyMs: latencyMs,
      latencyPriority: latencyPriority,
      healthStatus: healthStatus,
      regionHealthStatus: regionHealthStatus,
      regionHealthLastCheckedAt: regionHealthLastCheckedAt,
      regionHealthReasonCode: regionHealthReasonCode,
      publicIp: publicIp,
      tierRestriction: tierRestriction,
      premiumOnly: premiumOnly,
      supportedProtocols: supportedProtocols,
    );
  }

  static String? _normalizeCountryName(
      String? rawCountry, String? countryCode) {
    final country = rawCountry?.trim();
    final code = (countryCode ?? '').trim().toUpperCase();
    if (country == null ||
        country.isEmpty ||
        (country.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(country))) {
      return _countryNames[code] ?? (country?.toUpperCase());
    }
    return country;
  }

  static const Map<String, String> _countryNames = <String, String>{
    'US': 'United States',
    'DE': 'Germany',
    'FI': 'Finland',
    'SG': 'Singapore',
    'NL': 'Netherlands',
    'GB': 'United Kingdom',
    'FR': 'France',
    'CA': 'Canada',
    'MX': 'Mexico',
    'JP': 'Japan',
    'AU': 'Australia',
    'NZ': 'New Zealand',
    'KR': 'South Korea',
    'IN': 'India',
    'IE': 'Ireland',
    'IT': 'Italy',
    'ES': 'Spain',
    'PL': 'Poland',
    'NO': 'Norway',
    'SE': 'Sweden',
    'CH': 'Switzerland',
    'AT': 'Austria',
    'BE': 'Belgium',
    'PT': 'Portugal',
    'RO': 'Romania',
    'UA': 'Ukraine',
    'TR': 'Turkey',
    'IL': 'Israel',
    'ZA': 'South Africa',
    'AE': 'United Arab Emirates',
  };
}
