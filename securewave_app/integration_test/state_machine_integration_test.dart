import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import '../test/state_machine/state_machine_test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  testWidgets('state machine remains deterministic across repeated cycles',
      (tester) async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 25),
      disconnectDelay: const Duration(milliseconds: 20),
    );
    final api = FakeApiClient(
      config: config,
      metricsSnapshot: const {'health': 'ok'},
    );
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    final prefs = container.read(preferencesProvider.notifier);
    final rng = Random(42);

    for (var i = 0; i < 50; i += 1) {
      await notifier.connect();
      if (rng.nextBool()) {
        await prefs.setAutoConnect(rng.nextBool());
      }
      await notifier.disconnect();
      await settleStateMachine(turns: 8);
      final state = container.read(vpnStateProvider);
      expect(state.status, VpnStatus.disconnected);
      expect(state.errorMessage, isNull);
    }

    expect(container.read(vpnStateProvider.notifier).debugHasActiveOperation,
        isFalse);
    expect(
        container.read(vpnStateProvider.notifier).debugHasRateTimer, isFalse);
  });
}
