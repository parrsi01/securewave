import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
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

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');

    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
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

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();

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

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    expect(container.read(vpnStateProvider).status, VpnStatus.error);
  });

  test('duplicate connect requests remain single-flight', () async {
    final gate = Completer<void>();
    final service = ControlledVpnService(
      connectGate: gate,
      disconnectDelay: Duration.zero,
      capabilities: const VpnCapabilities(
        wireGuard: true,
        openVpn: false,
        ikev2: false,
      ),
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

    final notifier = container.read(vpnStateProvider.notifier);
    final f1 = notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connecting,
    );
    final f2 = notifier.connect();

    gate.complete();
    await Future.wait([f1, f2]);

    expect(service.connectCalls, 1);
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
  });

  test('preserves actionable WireGuard stale-interface error message',
      () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      connectError: VpnServiceException(
        'vpn_connect_failed',
        'WireGuard interface already exists (stale previous session).',
      ),
      capabilities: const VpnCapabilities(
        wireGuard: true,
        openVpn: false,
        ikev2: false,
      ),
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

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.wireGuard);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorMessage, contains('already exists'));
  });

  test('maps legacy 502 provisioning errors to protocol unavailable', () async {
    final service = ControlledVpnService(
      connectDelay: Duration.zero,
      capabilities: const VpnCapabilities(
        wireGuard: true,
        openVpn: true,
        ikev2: true,
      ),
    );
    final fakeApi = FakeApiClient(
      config: testAppConfig(),
      shouldFailProfile: true,
      profileError: DioException(
        requestOptions: RequestOptions(path: '/vpn/profile'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/vpn/profile'),
          statusCode: 502,
          data: const {
            'error': {
              'message': 'Failed to provision IKEv2 certificate profile.',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => testAppConfig()),
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(fakeApi),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.ikev2);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorKind, VpnErrorKind.protocolUnavailable);
    expect(state.errorMessage, contains('IKEv2'));
  });
}
