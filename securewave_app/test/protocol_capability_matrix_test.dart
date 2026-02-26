import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/vpn/protocol_capabilities.dart';

void main() {
  test('matrix marks protocol unavailable when native runtime is missing', () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: false,
      ikev2InstallHint: 'Install strongSwan and NetworkManager plugin.',
    );

    final result = ProtocolCapabilityMatrix.evaluate(
      nativeCapabilities: caps,
      backendEnabledProtocols: const <VpnProtocol>{
        VpnProtocol.wireGuard,
        VpnProtocol.openVpn,
        VpnProtocol.ikev2,
      },
      platformOverride: VpnClientPlatform.linux,
    );

    final openvpn =
        result.firstWhere((item) => item.protocol == VpnProtocol.openVpn);
    final ikev2 =
        result.firstWhere((item) => item.protocol == VpnProtocol.ikev2);

    expect(openvpn.available, isTrue);
    expect(ikev2.available, isFalse);
    expect(ikev2.unavailableReason, contains('strongSwan'));
  });

  test('matrix uses backend gating before native readiness', () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: true,
    );

    final result = ProtocolCapabilityMatrix.evaluate(
      nativeCapabilities: caps,
      backendEnabledProtocols: const <VpnProtocol>{VpnProtocol.wireGuard},
      platformOverride: VpnClientPlatform.windows,
    );

    final openvpn =
        result.firstWhere((item) => item.protocol == VpnProtocol.openVpn);

    expect(openvpn.available, isFalse);
    expect(openvpn.unavailableReason, contains('disabled by backend policy'));
  });

  test('matrix returns macOS entitlement warning when runtime is unavailable',
      () {
    const caps = VpnCapabilities(
      wireGuard: false,
      openVpn: false,
      ikev2: false,
      macosEntitlementWarning: 'Network Extension entitlements are missing.',
    );

    final result = ProtocolCapabilityMatrix.evaluate(
      nativeCapabilities: caps,
      backendEnabledProtocols: const <VpnProtocol>{
        VpnProtocol.wireGuard,
        VpnProtocol.openVpn,
        VpnProtocol.ikev2,
      },
      platformOverride: VpnClientPlatform.macos,
    );

    final ikev2 =
        result.firstWhere((item) => item.protocol == VpnProtocol.ikev2);
    expect(ikev2.available, isFalse);
    expect(ikev2.unavailableReason, contains('Network Extension'));
  });

  test('matrix marks Linux protocol unavailable when elevation is missing', () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: true,
      linuxElevationAvailable: false,
      linuxElevationHint: 'pkexec/polkit required',
    );

    final result = ProtocolCapabilityMatrix.evaluate(
      nativeCapabilities: caps,
      backendEnabledProtocols: const <VpnProtocol>{
        VpnProtocol.wireGuard,
        VpnProtocol.openVpn,
        VpnProtocol.ikev2,
      },
      platformOverride: VpnClientPlatform.linux,
    );

    final openvpn =
        result.firstWhere((item) => item.protocol == VpnProtocol.openVpn);
    expect(openvpn.available, isFalse);
    expect(openvpn.unavailableReason, contains('pkexec/polkit'));
  });
}
