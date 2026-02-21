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
    final requested =
        selected == VpnProtocol.auto ? _autoPreferred(capabilities) : selected;
    if (requested == null) {
      return ProtocolResolution(
        selected: selected,
        effective: VpnProtocol.auto,
        backendProtocol: VpnProtocol.auto,
        error: 'No supported VPN runtime is available on this device.',
      );
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
    switch (protocol) {
      case VpnProtocol.auto:
        return false;
      case VpnProtocol.wireGuard:
        return capabilities.wireGuard;
      case VpnProtocol.openVpn:
        return capabilities.openVpn;
      case VpnProtocol.ikev2:
        return capabilities.ikev2;
    }
  }

  String _unsupportedProtocolMessage(
    VpnProtocol protocol,
    VpnCapabilities capabilities,
  ) {
    if (protocol == VpnProtocol.wireGuard) {
      return capabilities.wireGuardInstallHint ??
          'WireGuard runtime is not available on this device.';
    }
    return '${vpnProtocolLabel(protocol)} is not available on this build. '
        'Select a different protocol or switch to Automatic.';
  }

  VpnProtocol? _autoPreferred(VpnCapabilities capabilities) {
    if (capabilities.wireGuard) return VpnProtocol.wireGuard;
    if (capabilities.openVpn) return VpnProtocol.openVpn;
    if (capabilities.ikev2) return VpnProtocol.ikev2;
    return null;
  }
}
