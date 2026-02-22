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
      if (capabilities.wireGuard) VpnProtocol.wireGuard,
      if (capabilities.openVpn) VpnProtocol.openVpn,
      if (capabilities.ikev2) VpnProtocol.ikev2,
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
      if (availableProtocols.length > 1) {
        return ProtocolResolution(
          selected: selected,
          effective: VpnProtocol.auto,
          backendProtocol: VpnProtocol.auto,
          error: 'Automatic protocol selection is disabled. '
              'Multiple VPN runtimes are available. Select WireGuard, '
              'OpenVPN, or IKEv2/IPSec explicitly.',
        );
      }
      requested = availableProtocols.first;
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
    if (protocol == VpnProtocol.openVpn) {
      return capabilities.openVpnInstallHint ??
          'OpenVPN runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.ikev2) {
      return capabilities.ikev2InstallHint ??
          'IKEv2/IPsec runtime is not available on this device.';
    }
    return '${vpnProtocolLabel(protocol)} is not available on this build. '
        'Select a different protocol or switch to Automatic.';
  }
}
