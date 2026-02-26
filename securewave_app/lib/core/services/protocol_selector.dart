import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import 'vpn_service.dart';

class ProtocolResolution {
  const ProtocolResolution({
    required this.selected,
    required this.effective,
    required this.backendProtocol,
    this.warning,
    this.error,
  });

  final VpnProtocol selected;
  final VpnProtocol effective;
  final VpnProtocol backendProtocol;
  final String? warning;
  final String? error;

  bool get isConnectable => error == null;
}

class ProtocolSelector {
  const ProtocolSelector();

  ProtocolResolution resolve({
    required VpnProtocol selected,
    required VpnCapabilities capabilities,
  }) {
    final availableProtocols = <VpnProtocol>[
      if (_supportsProtocol(VpnProtocol.wireGuard, capabilities))
        VpnProtocol.wireGuard,
      if (_supportsProtocol(VpnProtocol.openVpn, capabilities))
        VpnProtocol.openVpn,
      if (_supportsProtocol(VpnProtocol.ikev2, capabilities)) VpnProtocol.ikev2,
    ];

    VpnProtocol? requested;
    if (selected == VpnProtocol.auto) {
      if (availableProtocols.isEmpty) {
        return ProtocolResolution(
          selected: selected,
          effective: VpnProtocol.auto,
          backendProtocol: VpnProtocol.auto,
          error: 'No supported VPN runtime is available on this device.',
        );
      }
      requested = availableProtocols.first;
      if (availableProtocols.length > 1) {
        return ProtocolResolution(
          selected: selected,
          effective: requested,
          backendProtocol: requested,
          warning:
              'Automatic selected ${vpnProtocolLabel(requested)} based on local runtime availability.',
        );
      }
    } else {
      requested = selected;
    }

    if (!_supportsProtocol(requested, capabilities)) {
      return ProtocolResolution(
        selected: selected,
        effective: requested,
        backendProtocol: requested,
        error: _unsupportedProtocolMessage(requested, capabilities),
      );
    }

    return ProtocolResolution(
      selected: selected,
      effective: requested,
      backendProtocol: requested,
    );
  }

  bool _supportsProtocol(VpnProtocol protocol, VpnCapabilities capabilities) {
    final runtimeAvailable = switch (protocol) {
      VpnProtocol.auto => false,
      VpnProtocol.wireGuard => capabilities.wireGuard,
      VpnProtocol.openVpn => capabilities.openVpn,
      VpnProtocol.ikev2 => capabilities.ikev2,
    };
    if (!runtimeAvailable) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'linux' &&
        (protocol == VpnProtocol.wireGuard ||
            protocol == VpnProtocol.openVpn ||
            protocol == VpnProtocol.ikev2) &&
        !capabilities.linuxElevationAvailable) {
      return false;
    }
    switch (protocol) {
      case VpnProtocol.auto:
        return false;
      case VpnProtocol.wireGuard:
        return true;
      case VpnProtocol.openVpn:
        return true;
      case VpnProtocol.ikev2:
        return true;
    }
  }

  String _unsupportedProtocolMessage(
    VpnProtocol protocol,
    VpnCapabilities capabilities,
  ) {
    if (protocol == VpnProtocol.wireGuard) {
      if (platform.operatingSystem.name.toLowerCase() == 'linux' &&
          capabilities.wireGuard &&
          !capabilities.linuxElevationAvailable) {
        return capabilities.linuxElevationHint ??
            'WireGuard on Linux requires elevation (pkexec/polkit or root).';
      }
      return capabilities.wireGuardInstallHint ??
          'WireGuard runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.openVpn) {
      if (platform.operatingSystem.name.toLowerCase() == 'linux' &&
          capabilities.openVpn &&
          !capabilities.linuxElevationAvailable) {
        return capabilities.linuxElevationHint ??
            'OpenVPN on Linux requires elevation (pkexec/polkit or root).';
      }
      return capabilities.openVpnInstallHint ??
          'OpenVPN runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.ikev2) {
      if (platform.operatingSystem.name.toLowerCase() == 'linux' &&
          capabilities.ikev2 &&
          !capabilities.linuxElevationAvailable) {
        return capabilities.linuxElevationHint ??
            'IKEv2 on Linux requires elevation (pkexec/polkit or root).';
      }
      return capabilities.ikev2InstallHint ??
          'IKEv2/IPsec runtime is not available on this device.';
    }
    return '${vpnProtocolLabel(protocol)} is not available on this build. '
        'Select a different protocol or switch to Automatic.';
  }
}
