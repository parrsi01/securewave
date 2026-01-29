import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  test('MockVpnService connects and disconnects with delays', () async {
    final service = MockVpnService(connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.getStatus(), VpnStatus.disconnected);

    final connected = await service.connect();
    expect(connected, VpnStatus.connected);
    expect(service.getStatus(), VpnStatus.connected);

    final disconnected = await service.disconnect();
    expect(disconnected, VpnStatus.disconnected);
    expect(service.getStatus(), VpnStatus.disconnected);
  });
}
