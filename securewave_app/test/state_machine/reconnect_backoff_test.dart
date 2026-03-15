import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/core/state/vpn_state_machine.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('reconnect waits for the configured disconnect backoff', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = FakeApiClient(config: config);
    final container = buildVpnContainer(
      service: service,
      apiClient: api,
      config: const VpnStateMachineConfig(
        reconnectDelayAfterDisconnect: Duration(milliseconds: 80),
      ),
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );

    await notifier.disconnect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
      timeout: const Duration(seconds: 3),
    );

    final stopwatch = Stopwatch()..start();
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(60));
  });
}
