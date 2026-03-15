import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('switchServer fetches a new profile and reconnects when active',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');
    await notifier.connect();
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(api.profileFetchCalls, 1);

    await notifier.switchServer('de-fra');
    await settleStateMachine(turns: 40);

    final state = container.read(vpnStateProvider);
    expect(state.selectedServerId, 'de-fra');
    expect(state.status, VpnStatus.connected);
    expect(api.profileFetchCalls, greaterThanOrEqualTo(2));
    expect(service.disconnectCalls, greaterThanOrEqualTo(1));
    expect(service.connectCalls, greaterThanOrEqualTo(2));
  });
}
