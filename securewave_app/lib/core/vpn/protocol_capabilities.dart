import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../services/vpn_service.dart';

enum VpnClientPlatform {
  windows,
  linux,
  macos,
  android,
  ios,
  unknown,
}

class VpnProtocolRequirement {
  const VpnProtocolRequirement({
    required this.key,
    required this.description,
  });

  final String key;
  final String description;
}

class VpnProtocolAvailability {
  const VpnProtocolAvailability({
    required this.protocol,
    required this.declaredByPlatform,
    required this.backendEnabled,
    required this.nativeRuntimeReady,
    required this.available,
    required this.requirements,
    this.unavailableReason,
  });

  final VpnProtocol protocol;
  final bool declaredByPlatform;
  final bool backendEnabled;
  final bool nativeRuntimeReady;
  final bool available;
  final List<VpnProtocolRequirement> requirements;
  final String? unavailableReason;
}

class ProtocolCapabilityMatrix {
  const ProtocolCapabilityMatrix._();

  static List<VpnProtocol> orderedProtocols() {
    return const <VpnProtocol>[
      VpnProtocol.wireGuard,
      VpnProtocol.openVpn,
      VpnProtocol.ikev2,
    ];
  }

  static VpnClientPlatform currentPlatform() {
    switch (platform.operatingSystem.name.toLowerCase()) {
      case 'windows':
        return VpnClientPlatform.windows;
      case 'linux':
        return VpnClientPlatform.linux;
      case 'macos':
        return VpnClientPlatform.macos;
      case 'android':
        return VpnClientPlatform.android;
      case 'ios':
        return VpnClientPlatform.ios;
      default:
        return VpnClientPlatform.unknown;
    }
  }

  static String currentDeviceType() {
    switch (currentPlatform()) {
      case VpnClientPlatform.windows:
        return 'windows';
      case VpnClientPlatform.linux:
        return 'linux';
      case VpnClientPlatform.macos:
        return 'macos';
      case VpnClientPlatform.android:
        return 'android';
      case VpnClientPlatform.ios:
        return 'ios';
      case VpnClientPlatform.unknown:
        return 'unknown';
    }
  }

  static Set<VpnProtocol> declaredProtocols(VpnClientPlatform platform) {
    switch (platform) {
      case VpnClientPlatform.windows:
      case VpnClientPlatform.linux:
      case VpnClientPlatform.macos:
        return const <VpnProtocol>{
          VpnProtocol.wireGuard,
          VpnProtocol.openVpn,
          VpnProtocol.ikev2,
        };
      case VpnClientPlatform.android:
      case VpnClientPlatform.ios:
      case VpnClientPlatform.unknown:
        return const <VpnProtocol>{VpnProtocol.wireGuard};
    }
  }

  static List<VpnProtocolRequirement> requirementsFor(VpnProtocol protocol) {
    switch (protocol) {
      case VpnProtocol.auto:
        return const <VpnProtocolRequirement>[];
      case VpnProtocol.wireGuard:
        return const <VpnProtocolRequirement>[
          VpnProtocolRequirement(
            key: 'wireguard_runtime',
            description: 'A native WireGuard runtime must be available.',
          ),
        ];
      case VpnProtocol.openVpn:
        return const <VpnProtocolRequirement>[
          VpnProtocolRequirement(
            key: 'openvpn_runtime',
            description: 'A native OpenVPN runtime must be available.',
          ),
          VpnProtocolRequirement(
            key: 'server_openvpn_profile',
            description: 'Backend must provide a valid OpenVPN profile.',
          ),
        ];
      case VpnProtocol.ikev2:
        return const <VpnProtocolRequirement>[
          VpnProtocolRequirement(
            key: 'ikev2_runtime',
            description: 'OS/runtime support for IKEv2/IPsec is required.',
          ),
          VpnProtocolRequirement(
            key: 'server_ikev2_profile',
            description:
                'Backend must provide server identity and credentials.',
          ),
        ];
    }
  }

  static List<VpnProtocolAvailability> evaluate({
    required VpnCapabilities nativeCapabilities,
    required Set<VpnProtocol> backendEnabledProtocols,
    VpnClientPlatform? platformOverride,
  }) {
    final platform = platformOverride ?? currentPlatform();
    final declared = declaredProtocols(platform);
    final out = <VpnProtocolAvailability>[];

    for (final protocol in orderedProtocols()) {
      final declaredByPlatform = declared.contains(protocol);
      final backendEnabled = backendEnabledProtocols.contains(protocol);
      final nativeReady = switch (protocol) {
        VpnProtocol.auto => false,
        VpnProtocol.wireGuard => nativeCapabilities.wireGuard,
        VpnProtocol.openVpn => nativeCapabilities.openVpn,
        VpnProtocol.ikev2 => nativeCapabilities.ikev2,
      };

      String? reason;
      if (!declaredByPlatform) {
        reason =
            '${vpnProtocolLabel(protocol)} is not supported on this platform.';
      } else if (!backendEnabled) {
        reason =
            '${vpnProtocolLabel(protocol)} is disabled by backend policy or plan.';
      } else if (!nativeReady) {
        reason =
            _nativeUnavailableReason(platform, protocol, nativeCapabilities);
      }

      out.add(
        VpnProtocolAvailability(
          protocol: protocol,
          declaredByPlatform: declaredByPlatform,
          backendEnabled: backendEnabled,
          nativeRuntimeReady: nativeReady,
          available: declaredByPlatform && backendEnabled && nativeReady,
          requirements: requirementsFor(protocol),
          unavailableReason: reason,
        ),
      );
    }

    return out;
  }

  static String _nativeUnavailableReason(
    VpnClientPlatform platform,
    VpnProtocol protocol,
    VpnCapabilities nativeCapabilities,
  ) {
    if (protocol == VpnProtocol.wireGuard &&
        nativeCapabilities.wireGuardInstallHint != null) {
      return nativeCapabilities.wireGuardInstallHint!;
    }
    if (platform == VpnClientPlatform.macos) {
      return nativeCapabilities.macosEntitlementWarning ??
          'macOS VPN runtime is not configured for this build.';
    }
    return '${vpnProtocolLabel(protocol)} runtime is unavailable on this device.';
  }
}
