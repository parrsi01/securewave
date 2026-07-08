import 'package:platform_info/platform_info.dart' as platform_info;

import '../models/vpn_protocol.dart';
import '../services/linux_runtime_setup.dart';

enum PlatformRuntimeStatus {
  proven,
  implementedNotReleaseProven,
  uiOnly,
  blocked,
  unsupported,
}

enum SecureWaveRuntimePlatform {
  linux,
  windows,
  macos,
  android,
  ios,
  unsupported,
}

class ProtocolRuntimeTruth {
  const ProtocolRuntimeTruth({
    required this.protocol,
    required this.status,
    required this.guidance,
  });

  final VpnProtocol protocol;
  final PlatformRuntimeStatus status;
  final String guidance;
}

class PlatformReleaseTruth {
  const PlatformReleaseTruth({
    required this.platform,
    required this.artifactLabel,
    required this.uiStatus,
    required this.vpnRoutingStatus,
    required this.installAuthorization,
    required this.connectAuthorization,
    required this.guidance,
    required this.protocols,
  });

  final SecureWaveRuntimePlatform platform;
  final String artifactLabel;
  final PlatformRuntimeStatus uiStatus;
  final PlatformRuntimeStatus vpnRoutingStatus;
  final String installAuthorization;
  final String connectAuthorization;
  final String guidance;
  final List<ProtocolRuntimeTruth> protocols;

  bool get fullVpnRoutingProven =>
      vpnRoutingStatus == PlatformRuntimeStatus.proven;

  String get routingLabel => statusLabel(vpnRoutingStatus);

  static PlatformReleaseTruth current() {
    return forOperatingSystem(
      platform_info.platform.operatingSystem.name,
      linuxPackageMode: LinuxRuntimeSetup.currentPackageMode(),
    );
  }

  static PlatformReleaseTruth forOperatingSystem(
    String operatingSystem, {
    LinuxPackageMode linuxPackageMode = LinuxPackageMode.unknown,
  }) {
    switch (operatingSystem.trim().toLowerCase()) {
      case 'linux':
        return linux(linuxPackageMode: linuxPackageMode);
      case 'windows':
        return windows();
      case 'macos':
      case 'mac os':
      case 'darwin':
        return macos();
      case 'android':
        return android();
      case 'ios':
        return ios();
      default:
        return unsupported(operatingSystem);
    }
  }

  static PlatformReleaseTruth linux({
    LinuxPackageMode linuxPackageMode = LinuxPackageMode.unknown,
  }) {
    final portable = linuxPackageMode == LinuxPackageMode.portableArchive;
    return PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.linux,
      artifactLabel: LinuxRuntimeSetup.packageLabel(linuxPackageMode),
      uiStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      vpnRoutingStatus: portable
          ? PlatformRuntimeStatus.uiOnly
          : PlatformRuntimeStatus.implementedNotReleaseProven,
      installAuthorization: linuxPackageMode == LinuxPackageMode.debianPackage
          ? 'Admin authorization is required once during .deb installation.'
          : 'Portable archives do not install privileged VPN components.',
      connectAuthorization: linuxPackageMode == LinuxPackageMode.debianPackage
          ? 'Connect and disconnect should not prompt after the helper is installed.'
          : 'Portable mode has no no-prompt routing guarantee.',
      guidance: LinuxRuntimeSetup.guidanceFor(linuxPackageMode),
      protocols: const [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.implementedNotReleaseProven,
          guidance: 'Linux WireGuard uses wg-quick when host tooling and '
              'privileges are available. Release proof still requires a clean '
              'VM routing test.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.implementedNotReleaseProven,
          guidance: 'Linux OpenVPN depends on host OpenVPN tooling and a '
              'backend-issued profile. It must fail closed when the runtime is '
              'missing.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'Linux IKEv2 is unavailable until the strongSwan profile '
              'import/start path is implemented.',
        ),
      ],
    );
  }

  static PlatformReleaseTruth windows() {
    return const PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.windows,
      artifactLabel: 'Windows x64 installer',
      uiStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      vpnRoutingStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      installAuthorization:
          'WireGuard for Windows must be installed before routing can work.',
      connectAuthorization:
          'Tunnel service install/uninstall may require Windows privileges.',
      guidance: 'Windows routing is WireGuard-only in current source and is '
          'not release-proven until the installer and service path pass on a '
          'Windows host.',
      protocols: [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.implementedNotReleaseProven,
          guidance:
              'Uses official WireGuard for Windows tunnel service tooling.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'OpenVPN is not wired in the Windows app path.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'IKEv2 is not wired in the Windows app path.',
        ),
      ],
    );
  }

  static PlatformReleaseTruth macos() {
    return const PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.macos,
      artifactLabel: 'macOS UI demo',
      uiStatus: PlatformRuntimeStatus.uiOnly,
      vpnRoutingStatus: PlatformRuntimeStatus.unsupported,
      installAuthorization:
          'No VPN install authorization applies because VPN routing is disabled.',
      connectAuthorization:
          'Connect and disconnect return unavailable until a Network Extension exists.',
      guidance: 'macOS builds are UI/demo only in current source. Full routing '
          'requires a signed Network Extension or WireGuardKit integration.',
      protocols: [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'No macOS Network Extension tunnel provider is present.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'OpenVPN is not wired in the macOS app path.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'IKEv2 is not wired in the macOS app path.',
        ),
      ],
    );
  }

  static PlatformReleaseTruth android() {
    return const PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.android,
      artifactLabel: 'Android APK',
      uiStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      vpnRoutingStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      installAuthorization:
          'Android VPN consent is required through the operating system.',
      connectAuthorization:
          'The OS may prompt when VPN consent has not already been granted.',
      guidance: 'Android WireGuard is implemented but still needs signed '
          'artifact and device routing proof before public release.',
      protocols: [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.implementedNotReleaseProven,
          guidance: 'Uses Android VpnService and WireGuard backend.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'OpenVPN is not wired in the Android app path.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'IKEv2 is not wired in the Android app path.',
        ),
      ],
    );
  }

  static PlatformReleaseTruth ios() {
    return const PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.ios,
      artifactLabel: 'iOS TestFlight/App Store build',
      uiStatus: PlatformRuntimeStatus.implementedNotReleaseProven,
      vpnRoutingStatus: PlatformRuntimeStatus.blocked,
      installAuthorization:
          'Apple signing and Network Extension entitlement approval are required.',
      connectAuthorization:
          'iOS manages VPN profile approval and tunnel-start prompts.',
      guidance: 'iOS is blocked for public release until signed archive, '
          'entitlements, and physical-device routing proof exist.',
      protocols: [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.blocked,
          guidance: 'WireGuard path requires signed Network Extension proof.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'OpenVPN is not wired in the iOS app path.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'IKEv2 is not wired in the iOS app path.',
        ),
      ],
    );
  }

  static PlatformReleaseTruth unsupported(String operatingSystem) {
    final label = operatingSystem.trim().isEmpty
        ? 'Unsupported platform'
        : operatingSystem.trim();
    return PlatformReleaseTruth(
      platform: SecureWaveRuntimePlatform.unsupported,
      artifactLabel: label,
      uiStatus: PlatformRuntimeStatus.unsupported,
      vpnRoutingStatus: PlatformRuntimeStatus.unsupported,
      installAuthorization: 'No supported install path exists.',
      connectAuthorization: 'Connect and disconnect must fail closed.',
      guidance: 'SecureWave does not support VPN routing on this platform.',
      protocols: const [
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.wireGuard,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'WireGuard is unavailable on this platform.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.openVpn,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'OpenVPN is unavailable on this platform.',
        ),
        ProtocolRuntimeTruth(
          protocol: VpnProtocol.ikev2,
          status: PlatformRuntimeStatus.unsupported,
          guidance: 'IKEv2 is unavailable on this platform.',
        ),
      ],
    );
  }

  static String statusLabel(PlatformRuntimeStatus status) {
    switch (status) {
      case PlatformRuntimeStatus.proven:
        return 'Proven';
      case PlatformRuntimeStatus.implementedNotReleaseProven:
        return 'Implemented, not release-proven';
      case PlatformRuntimeStatus.uiOnly:
        return 'UI-only';
      case PlatformRuntimeStatus.blocked:
        return 'Blocked';
      case PlatformRuntimeStatus.unsupported:
        return 'Unsupported';
    }
  }
}
