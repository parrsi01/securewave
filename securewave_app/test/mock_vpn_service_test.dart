import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MockVpnService connects and disconnects with delays', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2),
        contains('not available'));
    expect(service.getStatus(), VpnStatus.disconnected);

    final connected = await service.connect(protocol: VpnProtocol.wireGuard);
    expect(connected, VpnStatus.connected);
    expect(service.getStatus(), VpnStatus.connected);

    final disconnected = await service.disconnect();
    expect(disconnected, VpnStatus.disconnected);
    expect(service.getStatus(), VpnStatus.disconnected);
  });

  test(
      'ChannelVpnService exposes only WireGuard on the historical Linux baseline',
      () {
    final service = ChannelVpnService(allowFallback: false);

    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isTrue);
    expect(service.canConnectProtocol(VpnProtocol.openVpn), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.openVpn),
        contains('authenticated current-source'));
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2),
        contains('not available'));
  }, testOn: 'linux');

  test('MockVpnService refuses OpenVPN without authenticated evidence',
      () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.openVpn), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.openVpn),
        contains('authenticated current-source'));
    expect(
      () => service.connect(protocol: VpnProtocol.openVpn),
      throwsA(isA<VpnServiceException>()),
    );
  });
}
