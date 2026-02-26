import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('enabling auto-connect while authenticated triggers connect flow',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await container.read(preferencesProvider.notifier).setAutoConnect(false);
    await container.read(authSessionProvider).setSession(accessToken: 'token');
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, isNot(VpnStatus.connected));

    await container.read(preferencesProvider.notifier).setAutoConnect(true);
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(service.connectCalls, greaterThanOrEqualTo(1));
  });
}
