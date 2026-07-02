import 'package:flutter/foundation.dart';
import 'package:platform_info/platform_info.dart';

class PlatformReleaseTruth {
  const PlatformReleaseTruth({
    required this.platformName,
    required this.releaseLabel,
    required this.runtimeStatus,
    required this.summary,
    required this.detail,
    required this.isPublicRuntime,
    required this.canDemoUi,
  });

  final String platformName;
  final String releaseLabel;
  final String runtimeStatus;
  final String summary;
  final String detail;
  final bool isPublicRuntime;
  final bool canDemoUi;
}

class SecureWaveReleaseTruth {
  const SecureWaveReleaseTruth._();

  static const publicReleaseLabel = 'Linux desktop release candidate';
  static const publicModeLabel = 'Free mode now';
  static const premiumLabel = 'Premium coming soon';
  static const primaryProtocolLabel = 'WireGuard primary';
  static const openVpnBoundary =
      'OpenVPN remains limited to the covered Linux helper path.';
  static const ikev2Boundary = 'IKEv2 is not public v1 release-visible.';

  static PlatformReleaseTruth currentPlatform() {
    if (kIsWeb) {
      return const PlatformReleaseTruth(
        platformName: 'Web',
        releaseLabel: publicReleaseLabel,
        runtimeStatus: 'Native app required',
        summary: 'Web builds can present the interface, not run VPN tunnels.',
        detail:
            'Use the native Linux desktop release candidate for validated VPN runtime behavior.',
        isPublicRuntime: false,
        canDemoUi: true,
      );
    }

    switch (platform.operatingSystem) {
      case OperatingSystem.linux:
        return const PlatformReleaseTruth(
          platformName: 'Linux',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Public RC runtime',
          summary: 'Linux is the current public VPN release-candidate path.',
          detail:
              'WireGuard uses wg-quick. Install wireguard-tools and allow elevated runtime commands when prompted.',
          isPublicRuntime: true,
          canDemoUi: true,
        );
      case OperatingSystem.macOS:
        return const PlatformReleaseTruth(
          platformName: 'macOS',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Demo UI only',
          summary:
              'macOS can demo the shared app UI, but production VPN runtime is not promoted yet.',
          detail:
              'Real macOS tunneling requires the Apple Network Extension entitlement, signing path, and macOS tunnel target before release parity can be claimed.',
          isPublicRuntime: false,
          canDemoUi: true,
        );
      case OperatingSystem.iOS:
        return const PlatformReleaseTruth(
          platformName: 'iOS',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Simulator/demo UI only',
          summary:
              'iOS can demo the shared app UI, but real VPN runtime requires Apple entitlement and device testing.',
          detail:
              'The iOS Simulator cannot run the packet tunnel. Physical-device VPN testing needs valid Runner and PacketTunnel signing under an entitled Apple team.',
          isPublicRuntime: false,
          canDemoUi: true,
        );
      case OperatingSystem.android:
        return const PlatformReleaseTruth(
          platformName: 'Android',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Future platform',
          summary:
              'Android UI can follow the shared design system, but Android VPN runtime is outside public v1.',
          detail:
              'Do not claim Android VPN readiness until platform runtime, packaging, and release validation are complete.',
          isPublicRuntime: false,
          canDemoUi: true,
        );
      case OperatingSystem.windows:
        return const PlatformReleaseTruth(
          platformName: 'Windows',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Future platform',
          summary:
              'Windows UI can follow the shared design system, but Windows VPN runtime is outside public v1.',
          detail:
              'Do not claim Windows VPN readiness until native WireGuard integration, packaging, and release validation are complete.',
          isPublicRuntime: false,
          canDemoUi: true,
        );
      default:
        return const PlatformReleaseTruth(
          platformName: 'Unsupported platform',
          releaseLabel: publicReleaseLabel,
          runtimeStatus: 'Unsupported',
          summary:
              'This platform is not part of the current SecureWave public VPN release.',
          detail:
              'Use the validated Linux desktop release candidate for public runtime testing.',
          isPublicRuntime: false,
          canDemoUi: false,
        );
    }
  }
}
