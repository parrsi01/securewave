import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/release/platform_release_truth.dart';
import 'package:securewave_app/core/services/linux_runtime_setup.dart';

void main() {
  test('Linux missing helper guidance points to the .deb no-prompt model', () {
    final guidance = LinuxRuntimeSetup.missingHelperGuidance();

    expect(guidance, contains('privileged helper'));
    expect(guidance, contains('.deb'));
    expect(guidance, contains('no-connect-prompt'));
  });

  test('Linux portable package guidance is UI-only unless helper is installed',
      () {
    final truth = PlatformReleaseTruth.linux(
      linuxPackageMode: LinuxPackageMode.portableArchive,
    );

    expect(truth.artifactLabel, 'Linux portable');
    expect(truth.vpnRoutingStatus, PlatformRuntimeStatus.uiOnly);
    expect(truth.guidance, contains('launch the app UI only'));
    expect(truth.guidance, contains('privileged helper'));
  });

  test('Linux .deb guidance keeps install-time authorization separate', () {
    final truth = PlatformReleaseTruth.linux(
      linuxPackageMode: LinuxPackageMode.debianPackage,
    );

    expect(truth.artifactLabel, 'Linux .deb');
    expect(
      truth.vpnRoutingStatus,
      PlatformRuntimeStatus.implementedNotReleaseProven,
    );
    expect(
        truth.installAuthorization, contains('once during .deb installation'));
    expect(truth.connectAuthorization, contains('should not prompt'));
  });

  test('Linux IKEv2 remains unavailable until strongSwan start path is wired',
      () {
    final truth = PlatformReleaseTruth.linux();
    final ikev2 = truth.protocols.singleWhere(
      (item) => item.protocol == VpnProtocol.ikev2,
    );

    expect(ikev2.status, PlatformRuntimeStatus.unsupported);
    expect(ikev2.guidance, contains('strongSwan'));
    expect(ikev2.guidance, contains('unavailable'));
  });

  test('macOS is UI/demo only without Network Extension proof', () {
    final truth = PlatformReleaseTruth.forOperatingSystem('macos');

    expect(truth.uiStatus, PlatformRuntimeStatus.uiOnly);
    expect(truth.vpnRoutingStatus, PlatformRuntimeStatus.unsupported);
    expect(truth.guidance, contains('UI/demo only'));
    expect(truth.guidance, contains('Network Extension'));
  });

  test('Windows only claims current WireGuard integration', () {
    final truth = PlatformReleaseTruth.forOperatingSystem('windows');
    final wireGuard = truth.protocols.singleWhere(
      (item) => item.protocol == VpnProtocol.wireGuard,
    );
    final openVpn = truth.protocols.singleWhere(
      (item) => item.protocol == VpnProtocol.openVpn,
    );

    expect(wireGuard.status, PlatformRuntimeStatus.implementedNotReleaseProven);
    expect(openVpn.status, PlatformRuntimeStatus.unsupported);
    expect(truth.guidance, contains('WireGuard-only'));
  });

  test('unsupported platforms fail closed', () {
    final truth = PlatformReleaseTruth.forOperatingSystem('freebsd');

    expect(truth.platform, SecureWaveRuntimePlatform.unsupported);
    expect(truth.vpnRoutingStatus, PlatformRuntimeStatus.unsupported);
    expect(truth.guidance, contains('does not support VPN routing'));
    expect(truth.connectAuthorization, contains('fail closed'));
  });
}
