import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/core/state/vpn_state_machine.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('connect flow uses selected OpenVPN protocol when available', () async {
    final service = ControlledVpnService(
      capabilities: const VpnCapabilities(
        wireGuard: false,
        openVpn: true,
        ikev2: false,
      ),
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(service: service, apiClient: fakeApi);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await settleStateMachine(turns: 8);
    await notifier.selectProtocol(VpnProtocol.openVpn);
    await settleStateMachine(turns: 8);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
      timeout: const Duration(seconds: 3),
    );

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(service.lastConnectProtocol, VpnProtocol.openVpn);
    expect(service.lastProfile?['type'], 'openvpn');
  });

  test('unsupported selected protocol falls back to available runtime',
      () async {
    final service = ControlledVpnService(
      capabilities: const VpnCapabilities(
        wireGuard: true,
        openVpn: false,
        ikev2: false,
      ),
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(service: service, apiClient: fakeApi);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await settleStateMachine(turns: 8);
    await notifier.selectProtocol(VpnProtocol.openVpn);
    await settleStateMachine(turns: 8);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status != VpnStatus.connecting,
      timeout: const Duration(seconds: 3),
    );

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.desiredOn, isTrue);
    expect(service.connectCalls, 1);
    expect(service.lastConnectProtocol, VpnProtocol.wireGuard);
  });

  test('connect timeout moves to terminal failure state for IKEv2', () async {
    final service = ControlledVpnService(
      capabilities: const VpnCapabilities(
        wireGuard: false,
        openVpn: false,
        ikev2: true,
      ),
      connectDelay: const Duration(milliseconds: 200),
      disconnectDelay: Duration.zero,
    );
    final fakeApi = FakeApiClient(config: testAppConfig());
    final container = buildVpnContainer(
      service: service,
      apiClient: fakeApi,
      config: const VpnStateMachineConfig(
        connectTimeout: Duration(milliseconds: 40),
        profileFetchTimeout: Duration(milliseconds: 40),
      ),
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await settleStateMachine(turns: 8);
    await notifier.selectProtocol(VpnProtocol.ikev2);
    await settleStateMachine(turns: 8);
    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.error,
      timeout: const Duration(seconds: 3),
    );

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorKind, VpnErrorKind.backendError);
    expect(state.desiredOn, isTrue);
    expect(service.connectCalls, 1);
  });
}
