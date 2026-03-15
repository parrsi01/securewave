import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/tunnel_watchdog_service.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  test('TunnelWatchdogService emits server disconnect after repeated polls',
      () async {
    final samples = ListQueue<VpnRuntimeSnapshot>.of(<VpnRuntimeSnapshot>[
      const VpnRuntimeSnapshot(
        nativeStatus: VpnStatus.connected,
        hasNativeTrafficStats: true,
        sampleAvailable: true,
        trafficConnected: true,
        interfaceCompatible: true,
        reportedProtocol: VpnProtocol.wireGuard,
        rxBytes: 10,
        txBytes: 20,
        interfaceName: 'wg0',
      ),
      const VpnRuntimeSnapshot(
        nativeStatus: VpnStatus.disconnected,
        hasNativeTrafficStats: true,
        sampleAvailable: true,
        trafficConnected: false,
        interfaceCompatible: true,
        reportedProtocol: VpnProtocol.wireGuard,
        rxBytes: 10,
        txBytes: 20,
        interfaceName: 'wg0',
      ),
      const VpnRuntimeSnapshot(
        nativeStatus: VpnStatus.disconnected,
        hasNativeTrafficStats: true,
        sampleAvailable: true,
        trafficConnected: false,
        interfaceCompatible: true,
        reportedProtocol: VpnProtocol.wireGuard,
        rxBytes: 10,
        txBytes: 20,
        interfaceName: 'wg0',
      ),
    ]);
    final issues = <TunnelWatchdogIssue>[];
    late final TunnelWatchdogService watchdog;
    watchdog = TunnelWatchdogService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
        await watchdog.stop();
      },
      interval: const Duration(milliseconds: 10),
      serverDisconnectThreshold: 2,
    );

    await watchdog.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(issues, hasLength(1));
    expect(issues.single.type, TunnelWatchdogIssueType.serverDisconnect);
  });

  test('TunnelWatchdogService emits interface removal for incompatible tunnel',
      () async {
    final samples = ListQueue<VpnRuntimeSnapshot>.of(<VpnRuntimeSnapshot>[
      const VpnRuntimeSnapshot(
        nativeStatus: VpnStatus.connected,
        hasNativeTrafficStats: true,
        sampleAvailable: true,
        trafficConnected: true,
        interfaceCompatible: false,
        reportedProtocol: VpnProtocol.openVpn,
        rxBytes: 1,
        txBytes: 1,
        interfaceName: 'tun0',
      ),
      const VpnRuntimeSnapshot(
        nativeStatus: VpnStatus.connected,
        hasNativeTrafficStats: true,
        sampleAvailable: true,
        trafficConnected: true,
        interfaceCompatible: false,
        reportedProtocol: VpnProtocol.openVpn,
        rxBytes: 1,
        txBytes: 1,
        interfaceName: 'tun0',
      ),
    ]);
    final issues = <TunnelWatchdogIssue>[];
    late final TunnelWatchdogService watchdog;
    watchdog = TunnelWatchdogService(
      sample: () async => samples.isEmpty ? null : samples.removeFirst(),
      onIssue: (issue) async {
        issues.add(issue);
        await watchdog.stop();
      },
      interval: const Duration(milliseconds: 10),
      interfaceRemovalThreshold: 2,
    );

    await watchdog.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(issues, hasLength(1));
    expect(issues.single.type, TunnelWatchdogIssueType.interfaceRemoved);
  });
}
