import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/network_path.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/core/state/vpn_state_machine.dart';
import 'package:securewave_app/services/api_client.dart';

import 'state_machine/state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub flutter_secure_storage platform channel (unavailable in test harness)
    final store = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (methodCall.method) {
          case 'read':
            return key == null ? null : store[key];
          case 'write':
            if (key != null) store[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              store.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  });

  test('VpnStateNotifier transitions through connect and disconnect', () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => testAppConfig()),
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'test-token');

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
    );
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('VpnStateNotifier allows auto-select server', () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => testAppConfig()),
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'test-token');

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
  });

  test('VpnStateMachine exposes strict lifecycle transitions', () {
    expect(
      VpnStateMachine.transitionMap(),
      <VpnStatus, Set<VpnStatus>>{
        VpnStatus.disconnected: <VpnStatus>{
          VpnStatus.connecting,
          VpnStatus.reconnecting,
          VpnStatus.error,
        },
        VpnStatus.connecting: <VpnStatus>{
          VpnStatus.verifying,
          VpnStatus.connected,
          VpnStatus.reconnecting,
          VpnStatus.disconnected,
          VpnStatus.error,
        },
        VpnStatus.verifying: <VpnStatus>{
          VpnStatus.connected,
          VpnStatus.reconnecting,
          VpnStatus.disconnecting,
          VpnStatus.disconnected,
          VpnStatus.error,
        },
        VpnStatus.reconnecting: <VpnStatus>{
          VpnStatus.connecting,
          VpnStatus.verifying,
          VpnStatus.connected,
          VpnStatus.disconnecting,
          VpnStatus.disconnected,
          VpnStatus.error,
        },
        VpnStatus.connected: <VpnStatus>{
          VpnStatus.degraded,
          VpnStatus.reconnecting,
          VpnStatus.disconnecting,
          VpnStatus.error,
        },
        VpnStatus.degraded: <VpnStatus>{
          VpnStatus.connected,
          VpnStatus.reconnecting,
          VpnStatus.disconnecting,
          VpnStatus.error,
        },
        VpnStatus.disconnecting: <VpnStatus>{
          VpnStatus.disconnected,
          VpnStatus.reconnecting,
          VpnStatus.error,
        },
        VpnStatus.error: <VpnStatus>{
          VpnStatus.disconnected,
          VpnStatus.reconnecting,
        },
      },
    );
  });

  test(
      'VpnStateNotifier cannot remain connected when kill switch hooks present and network drops',
      () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => testAppConfig()),
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'test-token');

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.killSwitchActive, isTrue);
  });

  test('VpnStateNotifier can recover from kill-switch error on disconnect',
      () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => testAppConfig()),
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'test-token');

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    expect(container.read(vpnStateProvider).status, VpnStatus.error);

    await notifier.disconnect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.disconnected);
    expect(state.desiredOn, isFalse);
    expect(state.killSwitchActive, isFalse);
    expect(state.errorMessage, isNull);
  });

  test('VpnStateNotifier reconnects automatically when network returns',
      () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(
      service: service,
      apiClient: fakeApi,
      config: const VpnStateMachineConfig(
        reconnectDelayAfterDisconnect: Duration.zero,
        autoReconnectCooldown: Duration.zero,
      ),
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    expect(container.read(vpnStateProvider).killSwitchActive, isTrue);

    await notifier.handleConnectivityChange(hasNetwork: true);
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    final state = container.read(vpnStateProvider);
    expect(state.killSwitchActive, isFalse);
    expect(state.reconnectPending, isFalse);
    expect(state.errorMessage, isNull);
  });

  test('VpnStateNotifier restarts once on transport switch', () async {
    final service = ControlledVpnService(
      connectDelay: const Duration(milliseconds: 20),
      disconnectDelay: const Duration(milliseconds: 20),
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(
      service: service,
      apiClient: fakeApi,
      config: const VpnStateMachineConfig(
        reconnectDelayAfterDisconnect: Duration.zero,
      ),
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );
    await waitForCondition(() => !notifier.debugHasActiveOperation);

    final first = notifier.handleNetworkPathChange(
      previous: NetworkPathKind.wifi,
      current: NetworkPathKind.mobile,
    );
    final second = notifier.handleNetworkPathChange(
      previous: NetworkPathKind.mobile,
      current: NetworkPathKind.wifi,
    );
    await Future.wait(<Future<void>>[first, second]);
    await waitForCondition(() => service.disconnectCalls == 1);
    await waitForCondition(() => service.connectCalls == 2);
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    expect(service.disconnectCalls, 1);
    expect(service.connectCalls, 2);
    expect(container.read(vpnStateProvider).desiredOn, isTrue);
  });

  test('VpnStateNotifier safeShutdown disconnects the active tunnel', () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(
      service: service,
      apiClient: fakeApi,
      config: const VpnStateMachineConfig(
        reconnectDelayAfterDisconnect: Duration.zero,
      ),
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );

    await notifier.safeShutdown();

    final state = container.read(vpnStateProvider);
    expect(service.disconnectCalls, 1);
    expect(state.status, VpnStatus.disconnected);
    expect(state.desiredOn, isFalse);
    expect(state.reconnectPending, isFalse);
    expect(state.errorMessage, isNull);
  });
}
