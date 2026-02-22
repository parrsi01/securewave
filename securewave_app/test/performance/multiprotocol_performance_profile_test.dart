import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/screens/home/widgets/connection_ring.dart';
import 'package:securewave_app/screens/home/widgets/status_display.dart';
import 'package:securewave_app/services/api_client.dart';
import '../state_machine/state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  testWidgets('cold-start first interactive frame proxy stays below 1s',
      (tester) async {
    final service = ControlledVpnService(
      nativeAvailable: true,
      capabilities: const VpnCapabilities(
        wireGuard: true,
        openVpn: true,
        ikev2: true,
        windowsThreadSafe: true,
        linuxWireGuardInstalled: true,
        linuxElevationAvailable: true,
        macosEntitlementReady: true,
      ),
    );
    final appConfig = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://portal.example.invalid',
      upgradeUrl: 'https://upgrade.example.invalid',
      resetSessionOnBoot: false,
    );
    final apiClient = FakeApiClient(config: appConfig);

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWith((ref) => appConfig),
          vpnServiceProvider.overrideWithValue(service),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConnectionRing(),
                  SizedBox(height: 12),
                  StatusDisplay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    stopwatch.stop();

    final elapsedMs = stopwatch.elapsedMicroseconds / 1000.0;
    // Printed for profile capture in the report.
    // ignore: avoid_print
    print('PERF cold_start_interactive_frame_proxy_ms=$elapsedMs');
    expect(elapsedMs, lessThan(1000.0));
  });

  test('control-plane connect latency benchmark (per protocol)', () async {
    const cycles = 12;
    const warmupCycles = 2;
    final protocols = <VpnProtocol>[
      VpnProtocol.wireGuard,
      VpnProtocol.openVpn,
      VpnProtocol.ikev2,
    ];

    final appConfig = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://portal.example.invalid',
      upgradeUrl: 'https://upgrade.example.invalid',
      resetSessionOnBoot: false,
    );

    for (final protocol in protocols) {
      installSecureStorageMock();
      final service = ControlledVpnService(
        nativeAvailable: true,
        capabilities: const VpnCapabilities(
          wireGuard: true,
          openVpn: true,
          ikev2: true,
          windowsThreadSafe: true,
          linuxWireGuardInstalled: true,
          linuxElevationAvailable: true,
          macosEntitlementReady: true,
        ),
      );
      final apiClient = FakeApiClient(config: appConfig);
      final container = buildVpnContainer(
        service: service,
        apiClient: apiClient,
      );
      addTearDown(container.dispose);

      final notifier = container.read(vpnStateProvider.notifier);
      await notifier.selectProtocol(protocol);
      await settleStateMachine();

      final connectSamplesUs = <int>[];
      final disconnectSamplesUs = <int>[];

      for (var i = 0; i < cycles + warmupCycles; i += 1) {
        final connectSw = Stopwatch()..start();
        await notifier.connect();
        await waitForCondition(
          () => container.read(vpnStateProvider).status == VpnStatus.connected,
          timeout: const Duration(seconds: 3),
        );
        connectSw.stop();

        final disconnectSw = Stopwatch()..start();
        await notifier.disconnect();
        await waitForCondition(
          () =>
              container.read(vpnStateProvider).status == VpnStatus.disconnected,
          timeout: const Duration(seconds: 3),
        );
        disconnectSw.stop();

        if (i >= warmupCycles) {
          connectSamplesUs.add(connectSw.elapsedMicroseconds);
          disconnectSamplesUs.add(disconnectSw.elapsedMicroseconds);
        }
      }

      expect(connectSamplesUs, hasLength(cycles));
      expect(disconnectSamplesUs, hasLength(cycles));

      final connectAvgMs = _avgMs(connectSamplesUs);
      final connectP95Ms = _percentileMs(connectSamplesUs, 0.95);
      final disconnectAvgMs = _avgMs(disconnectSamplesUs);
      final disconnectP95Ms = _percentileMs(disconnectSamplesUs, 0.95);

      // ignore: avoid_print
      print(
        'PERF protocol=${protocol.name} '
        'connect_avg_ms=$connectAvgMs connect_p95_ms=$connectP95Ms '
        'disconnect_avg_ms=$disconnectAvgMs disconnect_p95_ms=$disconnectP95Ms',
      );

      expect(connectAvgMs, greaterThan(0));
      expect(disconnectAvgMs, greaterThan(0));
    }
  });
}

double _avgMs(List<int> samplesUs) {
  if (samplesUs.isEmpty) return 0;
  final sum = samplesUs.fold<int>(0, (a, b) => a + b);
  return sum / samplesUs.length / 1000.0;
}

double _percentileMs(List<int> samplesUs, double percentile) {
  if (samplesUs.isEmpty) return 0;
  final sorted = List<int>.from(samplesUs)..sort();
  final rank = (sorted.length - 1) * percentile;
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sorted[lower] / 1000.0;
  final t = rank - lower;
  return (sorted[lower] + (sorted[upper] - sorted[lower]) * t) / 1000.0;
}
