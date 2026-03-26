import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/runtime_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/vpn/mock_vpn_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = VpnProfile(
    deviceId: 1,
    deviceName: 'SecureWave Linux',
    deviceType: 'linux',
    protocol: 'wireguard',
    serverId: 'mock-server',
    serverLocation: 'Mock Region',
    issuedAt: null,
    expiresAt: null,
    wireguardConfig: '[Interface]\nAddress = 10.8.0.2/32\n',
    profile: <String, dynamic>{
      'type': 'wireguard',
      'wireguard_config': '[Interface]\nAddress = 10.8.0.2/32\n',
    },
    dnsServers: <String>['1.1.1.1'],
    adMalwareBlocking: 'on',
    dnsEnforcement: 'best_effort',
    killSwitchMode: 'enabled',
    killSwitchEnforcement: 'best_effort',
    peerRegistered: true,
    registrationStatus: null,
  );

  test('MockVpnAdapter connects without native runtime', () async {
    final adapter = MockVpnAdapter(
      config: const MockVpnAdapterConfig(
        forceFailure: false,
        latencyMs: 5,
        unstableMode: false,
      ),
    );
    final emitted = <VpnStatus>[];
    final sub = adapter.statusStream().listen(emitted.add);
    addTearDown(sub.cancel);

    final result = await adapter.connect(profile);
    await adapter.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(result.status, VpnStatus.connected);
    expect(result.assignedIp, '10.8.0.100');
    expect(
      emitted,
      containsAllInOrder(<VpnStatus>[
        VpnStatus.connecting,
        VpnStatus.connected,
        VpnStatus.disconnecting,
        VpnStatus.disconnected,
      ]),
    );
  });

  test('MockVpnAdapter supports forced failure', () async {
    final adapter = MockVpnAdapter(
      config: const MockVpnAdapterConfig(
        forceFailure: true,
        latencyMs: 1,
        unstableMode: false,
      ),
    );

    await expectLater(
      () => adapter.connect(profile),
      throwsA(isA<Exception>()),
    );
  });
}
