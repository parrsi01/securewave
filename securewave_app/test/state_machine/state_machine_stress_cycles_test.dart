import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('state machine stress cycles maintain invariants', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 15),
      disconnectDelay: const Duration(milliseconds: 12),
    );
    final api = FakeApiClient(
      config: config,
      metricsSnapshot: const {'health': 'ok', 'handshake_ms_avg': 12.4},
    );
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    final prefs = container.read(preferencesProvider.notifier);
    final rng = Random(7);

    const cycles = 120;
    var connectOps = 0;
    var disconnectOps = 0;

    for (var i = 0; i < cycles; i += 1) {
      final operations = <Future<void>>[];
      operations.add(notifier.connect());
      if (rng.nextBool()) {
        operations.add(
          Future<void>.delayed(
            Duration(milliseconds: 2 + rng.nextInt(6)),
            notifier.disconnect,
          ),
        );
      }
      if (rng.nextBool()) {
        operations.add(
          Future<void>.delayed(
            Duration(milliseconds: 1 + rng.nextInt(4)),
            notifier.connect,
          ),
        );
      }
      if (rng.nextInt(3) == 0) {
        operations.add(prefs.setAutoConnect(rng.nextBool()));
      }
      await Future.wait(operations);
      await settleStateMachine(turns: 10);

      final state = container.read(vpnStateProvider);
      expect(state.status, isNot(VpnStatus.connecting));
      expect(state.status, isNot(VpnStatus.disconnecting));
      expect(
        state.status == VpnStatus.connected ||
            state.status == VpnStatus.disconnected ||
            state.status == VpnStatus.error,
        isTrue,
      );
      if (state.desiredOn) {
        connectOps += 1;
      } else {
        disconnectOps += 1;
      }
      if (state.status == VpnStatus.error) {
        // Recover quickly; errors should not deadlock the state machine.
        await notifier.disconnect();
      }
    }

    await notifier.disconnect();
    await settleStateMachine(turns: 20);

    final finalState = container.read(vpnStateProvider);
    expect(finalState.status, VpnStatus.disconnected);
    expect(notifier.debugHasActiveOperation, isFalse);
    expect(notifier.debugHasRateTimer, isFalse);
    expect(connectOps + disconnectOps, cycles);
  });
}
