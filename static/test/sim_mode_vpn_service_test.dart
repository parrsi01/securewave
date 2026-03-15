import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

const _simMode =
    String.fromEnvironment('SECUREWAVE_SIM_MODE', defaultValue: 'false');

void main() {
  test('ChannelVpnService supports simulation mode without native channel',
      () async {
    if (_simMode.toLowerCase() != 'true') {
      return;
    }

    final service = ChannelVpnService();
    final caps = await service.getCapabilities();
    expect(caps.wireGuard, isTrue);
    expect(caps.openVpn, isTrue);
    expect(caps.ikev2, isTrue);

    final connected = await service.connect(
      protocol: VpnProtocol.wireGuard,
      profile: const <String, dynamic>{'wireguard_config': '[Interface]\n'},
    );
    expect(connected, VpnStatus.connected);

    final stats1 = await service.fetchTrafficStats();
    expect(stats1, isNotNull);
    expect(stats1!.connected, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    final stats2 = await service.fetchTrafficStats();
    expect(stats2, isNotNull);
    expect(stats2!.rxBytes >= stats1.rxBytes, isTrue);

    final disconnected = await service.disconnect();
    expect(disconnected, VpnStatus.disconnected);
  });
}
