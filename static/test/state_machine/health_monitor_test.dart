import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/health_monitor.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  test('HealthMonitorService emits no-tunnel failure when interface drops',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        httpsProbeOk: true,
        validationStatus: VpnValidationStatus.healthy,
        validationScore: 96,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: false,
        routePresent: false,
        pingReachable: false,
        trafficConnected: false,
        httpsProbeOk: false,
        validationStatus: VpnValidationStatus.unhealthy,
        validationScore: 15,
        failureType: VpnValidationFailureType.noTunnel,
        interfaceName: 'sw-wg',
      ),
    ]);
    final issues = <VpnHealthIssue>[];
    final issueReady = Completer<void>();
    late final HealthMonitorService monitor;
    monitor = HealthMonitorService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
        if (!issueReady.isCompleted) {
          issueReady.complete();
        }
        await monitor.stop();
      },
      interval: const Duration(milliseconds: 10),
    );

    await monitor.start();
    await issueReady.future.timeout(const Duration(milliseconds: 200));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.noTunnel);
  });

  test('HealthMonitorService emits degraded partial-connectivity issue',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        httpsProbeOk: false,
        dnsOk: true,
        validationStatus: VpnValidationStatus.degraded,
        validationScore: 78,
        failureType: VpnValidationFailureType.partialConnectivity,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        httpsProbeOk: false,
        dnsOk: true,
        validationStatus: VpnValidationStatus.degraded,
        validationScore: 78,
        failureType: VpnValidationFailureType.partialConnectivity,
        interfaceName: 'sw-wg',
      ),
    ]);
    final issues = <VpnHealthIssue>[];
    final issueReady = Completer<void>();
    late final HealthMonitorService monitor;
    monitor = HealthMonitorService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
        if (!issueReady.isCompleted) {
          issueReady.complete();
        }
        await monitor.stop();
      },
      interval: const Duration(milliseconds: 10),
      degradedFailureThreshold: 2,
    );

    await monitor.start();
    await issueReady.future.timeout(const Duration(milliseconds: 200));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.partialConnectivity);
    expect(issues.single.isDegraded, isTrue);
  });

  test('HealthMonitorService emits recovered callback after degradation clears',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        httpsProbeOk: false,
        dnsOk: true,
        validationStatus: VpnValidationStatus.degraded,
        validationScore: 78,
        failureType: VpnValidationFailureType.partialConnectivity,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        httpsProbeOk: false,
        dnsOk: true,
        validationStatus: VpnValidationStatus.degraded,
        validationScore: 78,
        failureType: VpnValidationFailureType.partialConnectivity,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        httpsProbeOk: true,
        dnsOk: true,
        validationStatus: VpnValidationStatus.healthy,
        validationScore: 95,
        interfaceName: 'sw-wg',
      ),
    ]);
    final issues = <VpnHealthIssue>[];
    final recoveries = <VpnHealthSnapshot>[];
    final recovered = Completer<void>();
    late final HealthMonitorService monitor;
    monitor = HealthMonitorService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
      },
      onRecovered: (snapshot) async {
        recoveries.add(snapshot);
        if (!recovered.isCompleted) {
          recovered.complete();
        }
        await monitor.stop();
      },
      interval: const Duration(milliseconds: 10),
      degradedFailureThreshold: 2,
    );

    await monitor.start();
    await recovered.future.timeout(const Duration(milliseconds: 300));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.partialConnectivity);
    expect(recoveries, hasLength(1));
  });

  test('HealthMonitorService emits packet-loss failure when loss is severe',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        policyRoutingPresent: true,
        httpsProbeOk: true,
        dnsOk: true,
        probeSuccesses: 1,
        probeAttempts: 3,
        packetLoss: 0.40,
        latencyMs: 120,
        validationStatus: VpnValidationStatus.unhealthy,
        validationScore: 64,
        failureType: VpnValidationFailureType.packetLoss,
        interfaceName: 'sw-wg',
      ),
    ]);
    final issues = <VpnHealthIssue>[];
    final issueReady = Completer<void>();
    late final HealthMonitorService monitor;
    monitor = HealthMonitorService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
        if (!issueReady.isCompleted) {
          issueReady.complete();
        }
        await monitor.stop();
      },
      interval: const Duration(milliseconds: 10),
      degradedFailureThreshold: 1,
    );

    await monitor.start();
    await issueReady.future.timeout(const Duration(milliseconds: 200));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.packetLoss);
    expect(issues.single.reason, contains('40'));
  });
}
