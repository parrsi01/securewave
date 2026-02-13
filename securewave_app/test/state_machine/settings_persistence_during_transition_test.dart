import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/state/preferences_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('test_settings_persistence_during_transition', () async {
    final config = testAppConfig(useMockApi: false);
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 120),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final vpnNotifier = container.read(vpnStateProvider.notifier);
    final connectFuture = vpnNotifier.connect();

    await waitForCondition(
      () => container.read(vpnStateProvider).isBusy,
      timeout: const Duration(seconds: 2),
    );

    await container.read(preferencesProvider.notifier).setAutoConnect(false);
    await connectFuture;
    await settleStateMachine(turns: 20);

    expect(container.read(preferencesProvider).autoConnect, isFalse);

    container.dispose();

    final reloaded = buildVpnContainer(
      service: ControlledVpnService(nativeAvailable: true),
      apiClient: FakeApiClient(config: config),
    );
    addTearDown(reloaded.dispose);

    final completer = Completer<void>();
    final sub = reloaded.listen<PreferencesState>(
      preferencesProvider,
      (_, next) {
        if (next.autoConnect == false && !completer.isCompleted) {
          completer.complete();
        }
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await completer.future.timeout(const Duration(seconds: 2));
    expect(reloaded.read(preferencesProvider).autoConnect, isFalse);
  });
}
