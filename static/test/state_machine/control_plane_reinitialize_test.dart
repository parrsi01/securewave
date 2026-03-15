import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('connect and disconnect reinitialize control-plane clients', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = FakeApiClient(config: config);
    final hookReasons = <String>[];
    api.registerControlPlaneReconnectHook(
      'test-hook',
      (event) async {
        hookReasons.add(event.reason);
      },
    );

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );

    expect(api.reinitializeCalls, 1);
    expect(api.reinitializeReasons, <String>['vpn_connected']);
    expect(hookReasons, <String>['vpn_connected']);

    await notifier.disconnect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
      timeout: const Duration(seconds: 3),
    );

    expect(api.reinitializeCalls, 2);
    expect(
      api.reinitializeReasons,
      <String>['vpn_connected', 'vpn_disconnected'],
    );
    expect(
      hookReasons,
      <String>['vpn_connected', 'vpn_disconnected'],
    );
  });
}
