import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('test_double_disconnect', () async {
    final config = testAppConfig(useMockApi: false);
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
      disconnectDelay: const Duration(milliseconds: 40),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);

    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await Future.wait([notifier.disconnect(), notifier.disconnect()]);
    await settleStateMachine(turns: 30);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.disconnected);
    expect(state.desiredOn, isFalse);
    expect(service.disconnectCalls, 1);
    expect(notifier.debugHasRateTimer, isFalse);
  });
}
