import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/runtime_flags.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String jwtWithExp(int expSeconds) {
    String enc(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${enc(<String, Object>{'alg': 'none', 'typ': 'JWT'})}.'
        '${enc(<String, Object>{'sub': 'user-1', 'exp': expSeconds})}.'
        'signature';
  }

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

  test('auth session availability triggers connect flow when automation defer is off',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
      authenticated: false,
    );
    addTearDown(container.dispose);

    // Enable auto-connect so the test can verify the trigger fires.
    await container.read(preferencesProvider.notifier).setAutoConnect(true);
    await settleStateMachine(turns: 5);

    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'opaque-token');
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );
    await settleStateMachine(turns: 20);

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(service.connectCalls, greaterThanOrEqualTo(1));
  });

  test('linux automation defers post-auth auto-connect until user taps connect',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(
      service: service,
      apiClient: api,
      authenticated: false,
      overrides: [
        deferPostAuthAutoConnectProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await settleStateMachine(turns: 20);
    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'opaque-token');
    await settleStateMachine(turns: 30);

    expect(service.connectCalls, 0);
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
    expect(container.read(vpnStateProvider).desiredOn, isFalse);
  });

  test('auto-connect is skipped when token is near expiry', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: Duration.zero,
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await container.read(preferencesProvider.notifier).setAutoConnect(false);
    final nearExpiryToken = jwtWithExp(
      DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 45))
              .millisecondsSinceEpoch ~/
          1000,
    );
    await container
        .read(authSessionProvider)
        .setSession(accessToken: nearExpiryToken);
    await settleStateMachine(turns: 20);

    await container.read(preferencesProvider.notifier).setAutoConnect(true);
    await settleStateMachine(turns: 40);

    expect(service.connectCalls, 0);
    expect(container.read(vpnStateProvider).status, isNot(VpnStatus.connected));
  });
}
