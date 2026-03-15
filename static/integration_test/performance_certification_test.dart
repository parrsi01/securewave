import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/screens/home/widgets/connection_ring.dart';
import 'package:securewave_app/screens/home/widgets/metrics_display.dart';
import 'package:securewave_app/screens/home/widgets/status_display.dart';
import 'package:securewave_app/ui/design/app_spacing.dart';

import '../test/state_machine/state_machine_test_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  testWidgets('collects performance certification metrics', (tester) async {
    final service = ControlledVpnService(
      nativeAvailable: true,
      connectDelay: const Duration(milliseconds: 24),
      disconnectDelay: const Duration(milliseconds: 18),
    );
    final api = FakeApiClient(
      config: testAppConfig(),
      metricsSnapshot: const {'health': 'ok', 'latency_ms': 15},
    );
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
                child: const Column(
                  children: [
                    Spacer(),
                    ConnectionRing(),
                    SizedBox(height: AppSpacing.space5),
                    StatusDisplay(),
                    SizedBox(height: AppSpacing.space5),
                    MetricsDisplay(),
                    Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notifier = container.read(vpnStateProvider.notifier);

    Future<Map<String, dynamic>> measureScenario(
      String name,
      Future<void> Function(void Function()) action,
    ) async {
      var peakRss = ProcessInfo.currentRss;
      final startRss = peakRss;

      void sample() {
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      sample();
      await action(sample);
      await settleStateMachine(turns: 12);
      await tester.pump(const Duration(milliseconds: 120));
      sample();
      final endRss = ProcessInfo.currentRss;

      return <String, dynamic>{
        'scenario': name,
        'start_rss_mb': _mb(startRss),
        'peak_rss_mb': _mb(peakRss),
        'end_rss_mb': _mb(endRss),
        'spike_mb': _mb(peakRss - startRss),
        'retained_mb': _mb(endRss - startRss),
      };
    }

    final cycleMemory = await measureScenario(
      'connect_disconnect_10_cycles',
      (sample) async {
        for (var i = 0; i < 10; i += 1) {
          await notifier.connect();
          await settleStateMachine(turns: 10);
          await tester.pump(const Duration(milliseconds: 240));
          sample();

          await notifier.disconnect();
          await settleStateMachine(turns: 10);
          await tester.pump(const Duration(milliseconds: 200));
          sample();
        }
      },
    );

    final serverMemory = await measureScenario(
      'rapid_server_switching',
      (sample) async {
        const serverIds = <String>[
          'us-chi',
          'us-nyc',
          'de-fra',
          'uk-lon',
          'sg-sin',
          'jp-tyo',
          'au-syd',
          'br-sao',
        ];
        for (var i = 0; i < 160; i += 1) {
          notifier.selectServer(serverIds[i % serverIds.length]);
          if (i % 8 == 0) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          sample();
        }
        notifier.selectServer(null);
      },
    );

    final protocolMemory = await measureScenario(
      'protocol_switching',
      (sample) async {
        for (var round = 0; round < 6; round += 1) {
          for (final protocol in VpnProtocol.values) {
            await notifier.selectProtocol(protocol);
            await tester.pump(const Duration(milliseconds: 12));
            sample();
          }
        }
      },
    );

    final lifecycleMemory = await measureScenario(
      'background_foreground_transitions',
      (sample) async {
        await notifier.connect();
        await settleStateMachine(turns: 10);
        await tester.pump(const Duration(milliseconds: 220));

        for (var i = 0; i < 20; i += 1) {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
          notifier.pauseRateUpdates();
          await tester.pump(const Duration(milliseconds: 40));
          sample();

          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          notifier.resumeRateUpdates();
          await tester.pump(const Duration(milliseconds: 40));
          sample();
        }

        await notifier.disconnect();
      },
    );

    await binding.watchPerformance(
      () async {
        for (var i = 0; i < 8; i += 1) {
          await notifier.connect();
          await settleStateMachine(turns: 8);
          await tester.pump(const Duration(milliseconds: 220));
          await notifier.disconnect();
          await settleStateMachine(turns: 8);
          await tester.pump(const Duration(milliseconds: 180));
        }
        for (var i = 0; i < 80; i += 1) {
          notifier.selectServer('server-$i');
          if (i % 4 == 0) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }
        for (final protocol in VpnProtocol.values) {
          await notifier.selectProtocol(protocol);
          await tester.pump(const Duration(milliseconds: 32));
        }
      },
      reportKey: 'frame_timings',
    );

    await binding.traceAction(
      () async {
        await notifier.connect();
        await settleStateMachine(turns: 8);
        await tester.pump(const Duration(milliseconds: 320));
        await notifier.disconnect();
        await settleStateMachine(turns: 8);
        await tester.pump(const Duration(milliseconds: 320));
      },
      reportKey: 'timeline_trace',
    );

    final timelineTrace =
        binding.reportData?['timeline_trace'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
    final traceEvents =
        timelineTrace['traceEvents'] as List<dynamic>? ?? const <dynamic>[];
    final shaderCompileEvents = traceEvents.where((event) {
      if (event is! Map) return false;
      final name = (event['name'] ?? '').toString().toLowerCase();
      final category = (event['cat'] ?? '').toString().toLowerCase();
      return name.contains('shader') ||
          name.contains('compileshader') ||
          (name.contains('compile') && category.contains('skia'));
    }).length;

    final state = container.read(vpnStateProvider);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['memory_scenarios'] = <Map<String, dynamic>>[
      cycleMemory,
      serverMemory,
      protocolMemory,
      lifecycleMemory,
    ];
    binding.reportData!['shader_compile_event_count'] = shaderCompileEvents;
    binding.reportData!['runtime_invariants'] = <String, dynamic>{
      'final_status': state.status.name,
      'active_operation': notifier.debugHasActiveOperation,
      'rate_timer_active': notifier.debugHasRateTimer,
      'profile_fetch_calls': api.profileFetchCalls,
      'connect_calls': service.connectCalls,
      'disconnect_calls': service.disconnectCalls,
    };

    expect(notifier.debugHasActiveOperation, isFalse);
    expect(notifier.debugHasRateTimer, isFalse);
    expect(state.status, VpnStatus.disconnected);
  });
}

double _mb(int bytes) =>
    double.parse((bytes / (1024 * 1024)).toStringAsFixed(2));
