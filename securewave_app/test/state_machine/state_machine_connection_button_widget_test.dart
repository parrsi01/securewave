import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/screens/home/widgets/connection_button.dart';

import 'state_machine_test_harness.dart';

Future<void> waitForVpnStatus(
  WidgetTester tester,
  ProviderContainer container,
  VpnStatus expected, {
  Duration timeout = const Duration(seconds: 3),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (container.read(vpnStateProvider).status != expected) {
    if (DateTime.now().isAfter(deadline)) {
      final state = container.read(vpnStateProvider);
      fail(
        'Timed out waiting for VPN status $expected. '
        'Current=${state.status}, desiredOn=${state.desiredOn}, busy=${state.isBusy}',
      );
    }
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  testWidgets('connection button remains stable under rapid taps',
      (tester) async {
    final config = testAppConfig();
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 80),
      disconnectDelay: const Duration(milliseconds: 80),
    );
    final api = FakeApiClient(config: config);

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: ConnectionButton())),
        ),
      ),
    );

    final button = find.byType(ConnectionButton);
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.tap(button);

    await tester.pump(const Duration(milliseconds: 250));

    unawaited(container.read(vpnStateProvider.notifier).disconnect());
    await waitForVpnStatus(tester, container, VpnStatus.disconnected);
    await tester.pump(const Duration(milliseconds: 20));

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.disconnected);
    expect(state.status, isNot(VpnStatus.error));
  });
}
