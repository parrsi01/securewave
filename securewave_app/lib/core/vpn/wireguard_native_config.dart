class WireGuardNativeConfig {
  const WireGuardNativeConfig({
    required this.serverId,
    required this.endpointHost,
    required this.endpointPort,
    required this.clientPrivateKey,
    required this.addressCidr,
    required this.dns,
    required this.allowedIps,
    required this.keepaliveSeconds,
    required this.serverPublicKey,
    this.presharedKey,
  });

  final String serverId;
  final String endpointHost;
  final int endpointPort;
  final String clientPrivateKey;
  final String addressCidr;
  final List<String> dns;
  final List<String> allowedIps;
  final int keepaliveSeconds;
  final String serverPublicKey;
  final String? presharedKey;

  factory WireGuardNativeConfig.fromProfilePayload(
    Map<String, dynamic> profile,
  ) {
    final rawConfig = (profile['wireguard_config']?.toString() ?? '').trim();
    if (rawConfig.isEmpty) {
      throw StateError('WireGuard profile is missing wireguard_config.');
    }
    final serverId = (profile['server_id']?.toString() ?? '').trim();
    return WireGuardNativeConfig.fromWgQuickConfig(
      rawConfig,
      serverId: serverId,
    );
  }

  factory WireGuardNativeConfig.fromWgQuickConfig(
    String rawConfig, {
    required String serverId,
  }) {
    final interfaceValues = <String, List<String>>{};
    final peerValues = <String, List<String>>{};
    var section = '';
    var peerSections = 0;

    void addValue(Map<String, List<String>> target, String key, String value) {
      final normalizedKey = key.trim().toLowerCase();
      final normalizedValue = value.trim();
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
      target.putIfAbsent(normalizedKey, () => <String>[]).add(normalizedValue);
    }

    for (final rawLine in rawConfig
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final commentIndex = line.indexOf('#');
      if (commentIndex >= 0) {
        line = line.substring(0, commentIndex).trim();
      }
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      if (lower == '[interface]') {
        section = 'interface';
        continue;
      }
      if (lower == '[peer]') {
        section = 'peer';
        peerSections += 1;
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (section == 'interface') {
        addValue(interfaceValues, key, value);
      } else if (section == 'peer') {
        addValue(peerValues, key, value);
      }
    }

    if (peerSections != 1) {
      throw StateError(
        'WireGuard profile must contain exactly one [Peer] section for Apple.',
      );
    }

    String requireSingle(
      Map<String, List<String>> source,
      String key,
      String label,
    ) {
      final value = source[key]?.join(',').trim() ?? '';
      if (value.isEmpty) {
        throw StateError('WireGuard profile missing $label.');
      }
      return value;
    }

    List<String> parseCsvValues(List<String>? values) {
      return (values ?? const <String>[])
          .expand((value) => value.split(','))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }

    final endpoint = requireSingle(
      peerValues,
      'endpoint',
      'Peer Endpoint',
    );
    final endpointParts = _parseEndpoint(endpoint);
    final addresses = parseCsvValues(interfaceValues['address']);
    if (addresses.isEmpty) {
      throw StateError('WireGuard profile missing Interface Address.');
    }
    final allowedIps = parseCsvValues(peerValues['allowedips']);
    if (allowedIps.isEmpty) {
      throw StateError('WireGuard profile missing Peer AllowedIPs.');
    }

    final keepaliveRaw =
        (peerValues['persistentkeepalive']?.join(',').trim() ?? '25');
    final keepaliveSeconds = int.tryParse(keepaliveRaw) ?? 25;
    final preshared = peerValues['presharedkey']?.join(',').trim();

    return WireGuardNativeConfig(
      serverId: serverId,
      endpointHost: endpointParts.$1,
      endpointPort: endpointParts.$2,
      clientPrivateKey: requireSingle(
        interfaceValues,
        'privatekey',
        'Interface PrivateKey',
      ),
      addressCidr: addresses.join(','),
      dns: parseCsvValues(interfaceValues['dns']),
      allowedIps: allowedIps,
      keepaliveSeconds: keepaliveSeconds,
      presharedKey: preshared == null || preshared.isEmpty ? null : preshared,
      serverPublicKey: requireSingle(
        peerValues,
        'publickey',
        'Peer PublicKey',
      ),
    );
  }

  static (String, int) _parseEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      throw StateError('WireGuard profile missing Peer Endpoint.');
    }
    if (trimmed.startsWith('[')) {
      final closing = trimmed.indexOf(']');
      final colon = trimmed.lastIndexOf(':');
      if (closing <= 0 || colon < closing + 1) {
        throw StateError('WireGuard endpoint is invalid: $trimmed');
      }
      final host = trimmed.substring(1, closing);
      final port = int.tryParse(trimmed.substring(colon + 1));
      if (host.isEmpty || port == null) {
        throw StateError('WireGuard endpoint is invalid: $trimmed');
      }
      return (host, port);
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon <= 0 || colon == trimmed.length - 1) {
      throw StateError('WireGuard endpoint is invalid: $trimmed');
    }
    final host = trimmed.substring(0, colon).trim();
    final port = int.tryParse(trimmed.substring(colon + 1).trim());
    if (host.isEmpty || port == null) {
      throw StateError('WireGuard endpoint is invalid: $trimmed');
    }
    return (host, port);
  }
}
