import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/vpn/wireguard_native_config.dart';

void main() {
  test('parses backend WireGuard config into Apple bridge payload fields', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32, fd00::2/128
DNS = 1.1.1.1, 9.9.9.9

[Peer]
PublicKey = server-public
PresharedKey = test-psk
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.securewave.example:51820
PersistentKeepalive = 21
''';

    final parsed = WireGuardNativeConfig.fromWgQuickConfig(
      config,
      serverId: 'de-nue-1',
    );

    expect(parsed.serverId, 'de-nue-1');
    expect(parsed.endpointHost, 'vpn.securewave.example');
    expect(parsed.endpointPort, 51820);
    expect(parsed.clientPrivateKey, 'test-private');
    expect(parsed.addressCidr, '10.0.0.2/32,fd00::2/128');
    expect(parsed.dns, <String>['1.1.1.1', '9.9.9.9']);
    expect(parsed.allowedIps, <String>['0.0.0.0/0', '::/0']);
    expect(parsed.keepaliveSeconds, 21);
    expect(parsed.serverPublicKey, 'server-public');
    expect(parsed.presharedKey, 'test-psk');
  });

  test('supports ipv6 endpoints in backend WireGuard config', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = [2001:db8::42]:443
''';

    final parsed = WireGuardNativeConfig.fromWgQuickConfig(
      config,
      serverId: 'us-chi-1',
    );

    expect(parsed.endpointHost, '2001:db8::42');
    expect(parsed.endpointPort, 443);
    expect(parsed.keepaliveSeconds, 25);
  });

  test('rejects multi-peer configs for Apple bridge phase 1', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32

[Peer]
PublicKey = server-public-1
AllowedIPs = 0.0.0.0/0
Endpoint = vpn-a.example:51820

[Peer]
PublicKey = server-public-2
AllowedIPs = ::/0
Endpoint = vpn-b.example:51820
''';

    expect(
      () => WireGuardNativeConfig.fromWgQuickConfig(
        config,
        serverId: 'multi-peer',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
