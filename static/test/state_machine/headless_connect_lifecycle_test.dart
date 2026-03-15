import 'dart:async';

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
          if (state == AppLifecycleState.detached) {
            notifier.safeShutdown();
            return;
          }
          if (state == AppLifecycleState.paused ||
              state == AppLifecycleState.inactive) {
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

  test('detached lifecycle triggers a safe tunnel shutdown', () async {
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
    final lifecycleObserver = AppLifecycleObserver(
      onStateChange: (state) {
        if (state == AppLifecycleState.detached) {
          notifier.safeShutdown();
          return;
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) {
          notifier.pauseRateUpdates();
          return;
        }
        if (state == AppLifecycleState.resumed) {
          notifier.resumeRateUpdates();
        }
      },
    );

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.detached);
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
    );

    final state = container.read(vpnStateProvider);
    expect(service.disconnectCalls, 1);
    expect(state.desiredOn, isFalse);
    expect(state.reconnectPending, isFalse);
  });

  test('detached shutdown reuses the in-flight disconnect', () async {
    final disconnectGate = Completer<void>();
    final service = ControlledVpnService(
      connectDelay: const Duration(milliseconds: 25),
      disconnectDelay: Duration.zero,
      disconnectGate: disconnectGate,
    );
    final api = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'test-token');

    final notifier = container.read(vpnStateProvider.notifier);
    final lifecycleObserver = AppLifecycleObserver(
      onStateChange: (state) {
        if (state == AppLifecycleState.detached) {
          notifier.safeShutdown();
          return;
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) {
          notifier.pauseRateUpdates();
          return;
        }
        if (state == AppLifecycleState.resumed) {
          notifier.resumeRateUpdates();
        }
      },
    );

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.detached);
    await waitForCondition(() => service.disconnectCalls == 1);

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.detached);
    await settleStateMachine(turns: 10);

    expect(service.disconnectCalls, 1);

    disconnectGate.complete();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
    );

    final state = container.read(vpnStateProvider);
    expect(state.desiredOn, isFalse);
    expect(state.reconnectPending, isFalse);
  });
}
