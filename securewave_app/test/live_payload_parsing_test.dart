import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';

void main() {
  test('ServerRegion keeps only WireGuard protocol metadata', () {
    final region = ServerRegion.fromJson({
      'server_id': 'de-nue-1',
      'location': 'Nuremberg',
      'country': 'Germany',
      'latency_ms': 0.051,
      'load_percent': 12.4,
      'region_health_status': 'up',
      'supported_protocols': ['wireguard', 'removed-protocol'],
      'premium_only': false,
    });

    expect(region.id, 'de-nue-1');
    expect(region.latencyMs, 0);
    expect(region.loadPercent, 12.4);
    expect(region.supportsProtocol('wireguard'), isTrue);
    expect(region.supportsProtocol('removed-protocol'), isFalse);
    expect(region.premiumOnly, isFalse);
  });

  test('ServerRegion ignores unknown protocol booleans', () {
    final region = ServerRegion.fromJson({
      'server_id': 'de-nue-1',
      'location': 'Nuremberg',
      'supports_wireguard': true,
      'supports_removed_protocol': true,
    });

    expect(region.supportsProtocol('wireguard'), isTrue);
    expect(region.supportsProtocol('removed-protocol'), isFalse);
  });

  test('VpnProfile strips legacy privileged WireGuard directives', () {
    final profile = VpnProfile.fromJson({
      'wireguard_config': '''[Interface]
PrivateKey = test-private-key
Address = 10.8.0.2/32
Table = off
PostUp = ip rule add table 51820
PostDown = ip rule del table 51820

[Peer]
PublicKey = test-public-key
Endpoint = 198.51.100.1:51820
AllowedIPs = 0.0.0.0/0, ::/0
''',
    });

    final config = profile.configForProtocol(VpnProtocol.wireGuard);
    expect(config, contains('PrivateKey = test-private-key'));
    expect(config, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    expect(config, isNot(contains('Table =')));
    expect(config, isNot(contains('PostUp =')));
    expect(config, isNot(contains('PostDown =')));
  });
}
