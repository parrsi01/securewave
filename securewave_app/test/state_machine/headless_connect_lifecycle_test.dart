import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/logging/app_logger.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test(
    'connect reaches connected once and stays connected through headless lifecycle events',
    () async {
      final service = ControlledVpnService(
        connectDelay: const Duration(milliseconds: 25),
        disconnectDelay: Duration.zero,
      );
      final api = FakeApiClient(config: testAppConfig());
      final container = buildVpnContainer(service: service, apiClient: api);
      addTearDown(container.dispose);
      await container
          .read(authSessionProvider)
          .setSession(accessToken: 'test-token');

      final notifier = container.read(vpnStateProvider.notifier);
      await settleStateMachine(turns: 8);

      final lifecycleObserver = AppLifecycleObserver(
        onStateChange: (state) {
          if (state == AppLifecycleState.resumed) {
            notifier.resumeRateUpdates();
            return;
          }
          if (state == AppLifecycleState.paused ||
              state == AppLifecycleState.inactive ||
              state == AppLifecycleState.detached) {
            notifier.pauseRateUpdates();
          }
        },
      );

      await notifier.connect();
      await waitForCondition(
        () => container.read(vpnStateProvider).status == VpnStatus.connected,
      );
      await settleStateMachine(turns: 20);

      await notifier.handleConnectivityChange(hasNetwork: true);
      lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settleStateMachine(turns: 20);

      final state = container.read(vpnStateProvider);
      final history = notifier.debugTransitionHistory;

      expect(state.desiredOn, isTrue);
      expect(state.status, VpnStatus.connected);
      expect(service.connectCalls, 1);
      expect(service.disconnectCalls, 0);
      expect(
        history.where((record) => record.to == VpnStatus.disconnecting),
        isEmpty,
      );
      expect(
        history.where((record) => record.to == VpnStatus.connected).length,
        1,
      );
    },
  );
}
