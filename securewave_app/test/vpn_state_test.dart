import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
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
    expect(container.read(vpnStateProvider).status, VpnStatus.error);
  });

  test('VpnStateNotifier disconnect normalizes error state to disconnected',
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
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.disconnected,
    );

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.disconnected);
    expect(state.desiredOn, isFalse);
    expect(state.errorKind, isNull);
    expect(state.errorMessage, isNull);
  });
}
