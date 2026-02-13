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

  test('test_timeout_handling', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 300),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
      config: const VpnStateMachineConfig(
        connectTimeout: Duration(milliseconds: 50),
        profileFetchTimeout: Duration(milliseconds: 50),
        disconnectTimeout: Duration(milliseconds: 50),
      ),
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();
    await settleStateMachine(turns: 30);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorMessage?.toLowerCase(), contains('timed out'));
    expect(container.read(vpnStateProvider.notifier).debugHasActiveOperation,
        isFalse);
  });
}
