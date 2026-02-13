import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('test_interleaved_connect_disconnect', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 120),
      disconnectDelay: const Duration(milliseconds: 60),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);

    final firstConnect = notifier.connect();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final disconnect = notifier.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final secondConnect = notifier.connect();

    await Future.wait([firstConnect, disconnect, secondConnect]);
    await settleStateMachine(turns: 60);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.desiredOn, isTrue);
    expect(service.connectCalls, greaterThanOrEqualTo(1));
    expect(container.read(vpnStateProvider.notifier).debugHasActiveOperation,
        isFalse);
    expect(state.errorMessage, isNull);
  });
}
