import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

String _jwtWithFutureExp() {
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final exp = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url.encode(utf8.encode('{"exp":$exp}'));
  return '$header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('enabling auto-connect while authenticated triggers connect flow',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await container.read(preferencesProvider.notifier).setAutoConnect(false);
    await container.read(authSessionProvider).setSession(accessToken: 'token');
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, isNot(VpnStatus.connected));

    await container.read(preferencesProvider.notifier).setAutoConnect(true);
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(service.connectCalls, greaterThanOrEqualTo(1));
  });

  test('restart restores session and auto-connects on startup', () async {
    installSecureStorageMock();
    final config = testAppConfig();
    final api = FakeApiClient(config: config);

    final firstService = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final first = buildVpnContainer(service: firstService, apiClient: api);
    await first.read(preferencesProvider.notifier).setAutoConnect(true);
    await first
        .read(authSessionProvider)
        .setSession(accessToken: _jwtWithFutureExp());
    await waitForCondition(
      () => first.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    first.dispose();

    final secondService = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final second = buildVpnContainer(
        service: secondService, apiClient: FakeApiClient(config: config));
    addTearDown(second.dispose);

    await waitForCondition(
      () => second.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    await settleStateMachine(turns: 20);

    expect(second.read(vpnStateProvider).status, VpnStatus.connected);
    expect(secondService.connectCalls, greaterThanOrEqualTo(1));
  });

  test('restart does not auto-connect when persisted auto-connect is off',
      () async {
    final store = installSecureStorageMock();
    store[SecureStorage.autoConnectKey] = 'false';
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final container = buildVpnContainer(
        service: service, apiClient: FakeApiClient(config: config));
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider)
        .setSession(accessToken: _jwtWithFutureExp());
    await waitForCondition(
      () => container.read(preferencesProvider).loaded,
      timeout: const Duration(seconds: 2),
    );
    await settleStateMachine(turns: 50);

    expect(container.read(preferencesProvider).autoConnect, isFalse);
    expect(container.read(vpnStateProvider).status, isNot(VpnStatus.connected));
    expect(service.connectCalls, 0);
  });
}
