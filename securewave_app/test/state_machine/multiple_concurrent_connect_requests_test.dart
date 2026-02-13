import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('test_multiple_concurrent_connect_requests', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 40),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);

    await Future.wait(
      List<Future<void>>.generate(20, (_) => notifier.connect()),
    );
    await settleStateMachine(turns: 40);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.desiredOn, isTrue);
    expect(service.connectCalls, 1);
    expect(notifier.debugHasActiveOperation, isFalse);
  });
}
