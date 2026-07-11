import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MockVpnService connects and disconnects with delays', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.ikev2), isTrue);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNull);
    expect(service.getStatus(), VpnStatus.disconnected);

    final connected = await service.connect(protocol: VpnProtocol.wireGuard);
    expect(connected, VpnStatus.connected);
    expect(service.getStatus(), VpnStatus.connected);

    final disconnected = await service.disconnect();
    expect(disconnected, VpnStatus.disconnected);
    expect(service.getStatus(), VpnStatus.disconnected);
  });

  test('ChannelVpnService starts Linux protocol availability fail closed', () {
    final service = ChannelVpnService(allowFallback: false);

    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isFalse);
    expect(service.canConnectProtocol(VpnProtocol.openVpn), isFalse);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNotNull);
  }, testOn: 'linux');
}
