import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/health_monitor.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  test('HealthMonitorService emits hard failure when interface drops',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: false,
        routePresent: false,
        pingReachable: false,
        trafficConnected: false,
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
    expect(issues.single.type, VpnHealthFailureType.hardFailure);
  });

  test('HealthMonitorService emits soft failure after repeated probe loss',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
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
      softFailureThreshold: 2,
    );

    await monitor.start();
    await issueReady.future.timeout(const Duration(milliseconds: 200));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.softFailure);
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
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: false,
        trafficConnected: true,
        interfaceName: 'sw-wg',
      ),
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
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
      softFailureThreshold: 2,
    );

    await monitor.start();
    await recovered.future.timeout(const Duration(milliseconds: 300));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.softFailure);
    expect(recoveries, hasLength(1));
  });

  test('HealthMonitorService emits handshake failure when handshake is stale',
      () async {
    final samples = ListQueue<VpnHealthSnapshot>.of(<VpnHealthSnapshot>[
      const VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        policyRoutingPresent: true,
        handshakeRecent: false,
        handshakeAgeSeconds: 45,
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
      handshakeFailureThreshold: 1,
    );

    await monitor.start();
    await issueReady.future.timeout(const Duration(milliseconds: 200));

    expect(issues, hasLength(1));
    expect(issues.single.type, VpnHealthFailureType.handshakeFailure);
    expect(issues.single.reason, contains('45s'));
  });
}
