import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/vpn/wireguard_linux_runtime_config.dart';

void main() {
  test(
      'preserves backend policy-routing hooks and strips legacy managed blocks',
      () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32
DNS = 1.1.1.1
Table = off
PostUp = ip route add default dev %i table 51820
PostDown = ip route flush table 51820

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.securewave.example:51820
''';

    final rendered = buildLinuxWireGuardRuntimeConfig(
      config,
      apiBaseUrl: 'https://api.securewave.example/api',
      uiAutomationEnabled: false,
    );

    expect(rendered, isNot(contains(secureWaveRouteGuardStartMarker)));
    expect(rendered, contains('Table = off'));
    expect(
        rendered, contains('PostUp = ip route add default dev %i table 51820'));
    expect(rendered, contains('PostDown = ip route flush table 51820'));
    expect(rendered.trimRight(), config.trimRight());
  });

  test('removes the legacy managed route guard block when present', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32
# SECUREWAVE_ROUTE_GUARD_START
PreUp = /bin/sh -c "iptables -P OUTPUT ACCEPT"
PostUp = /bin/sh -c "iptables -P OUTPUT DROP"
PreDown = /bin/sh -c "iptables -P OUTPUT ACCEPT"
# SECUREWAVE_ROUTE_GUARD_END
Table = off
PostUp = ip rule add not fwmark 51820 table 51820

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.securewave.example:51820
''';

    final first = buildLinuxWireGuardRuntimeConfig(
      config,
      apiBaseUrl: 'https://api.securewave.example/api',
      uiAutomationEnabled: false,
    );

    expect(first, isNot(contains(secureWaveRouteGuardStartMarker)));
    expect(first, isNot(contains(secureWaveRouteGuardEndMarker)));
    expect(first, isNot(contains('iptables -P OUTPUT DROP')));
    expect(first, contains('Table = off'));
    expect(
        first, contains('PostUp = ip rule add not fwmark 51820 table 51820'));
  });

  test('extracts the endpoint host from the backend profile', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.securewave.example:51820
''';

    expect(
      extractEndpointHostForKillSwitch(config),
      'vpn.securewave.example',
    );
  });

  test('leaves a hook-free config unchanged', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
''';

    final rendered = buildLinuxWireGuardRuntimeConfig(
      config,
      apiBaseUrl: 'http://127.0.0.1:8000/api',
      uiAutomationEnabled: false,
    );

    expect(rendered.trimRight(), config.trimRight());
  });

  test('adds an automation route guard for the API host when enabled', () {
    const config = '''
[Interface]
PrivateKey = test-private
Address = 10.0.0.2/32
Table = off

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.securewave.example:51820
''';

    final rendered = buildLinuxWireGuardRuntimeConfig(
      config,
      apiBaseUrl: 'https://api.securewave.example/api',
      uiAutomationEnabled: true,
    );

    expect(rendered, contains(secureWaveRouteGuardStartMarker));
    expect(rendered, contains('API_HOST=\\"api.securewave.example\\"'));
    expect(rendered, contains('ip route replace \\"\\\$ip/32\\" via'));
    expect(rendered, contains('ip route del \\"\\\$ip/32\\" 2>/dev/null || true'));
  });
}
