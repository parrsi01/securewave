import '../models/vpn_protocol.dart';
import '../models/vpn_protocol_catalog.dart';
import 'vpn_service.dart';

class ProtocolResolution {
  const ProtocolResolution({
    required this.selected,
    required this.effective,
    required this.backendProtocol,
    this.runtimeBlocked = false,
    this.backendBlocked = false,
    this.warning,
    this.error,
  });

  final VpnProtocol selected;
  final VpnProtocol effective;
  final VpnProtocol backendProtocol;
  final bool runtimeBlocked;
  final bool backendBlocked;
  final String? warning;
  final String? error;

  bool get isConnectable => error == null;
}

class ProtocolSelector {
  const ProtocolSelector();

  ProtocolResolution resolve({
    required VpnProtocol selected,
    required VpnCapabilities capabilities,
    VpnProtocolCatalog? catalog,
  }) {
    final runtimeAvailableProtocols = <VpnProtocol>[
      if (capabilities.wireGuard) VpnProtocol.wireGuard,
      if (capabilities.openVpn) VpnProtocol.openVpn,
      if (capabilities.ikev2) VpnProtocol.ikev2,
    ];
    final backendAvailableProtocols =
        catalog?.enabledProtocols() ?? runtimeAvailableProtocols.toSet();
    final connectableProtocols = runtimeAvailableProtocols
        .where(backendAvailableProtocols.contains)
        .toList(growable: false);

    VpnProtocol? requested;
    if (selected == VpnProtocol.auto) {
      if (connectableProtocols.isEmpty) {
        if (runtimeAvailableProtocols.isEmpty) {
          return ProtocolResolution(
            selected: selected,
            effective: VpnProtocol.auto,
            backendProtocol: VpnProtocol.auto,
            runtimeBlocked: true,
            error: 'No supported VPN runtime is available on this device.',
          );
        }
        return ProtocolResolution(
          selected: selected,
          effective: VpnProtocol.auto,
          backendProtocol: VpnProtocol.auto,
          backendBlocked: catalog != null,
          error: catalog == null
              ? 'No supported VPN runtime is available on this device.'
              : 'No VPN protocol is currently enabled by the backend for this '
                  'device, plan, or selected server.',
        );
      }
      if (connectableProtocols.contains(VpnProtocol.wireGuard)) {
        requested = VpnProtocol.wireGuard;
      } else if (connectableProtocols.contains(VpnProtocol.openVpn)) {
        requested = VpnProtocol.openVpn;
      } else {
        requested = VpnProtocol.ikev2;
      }
      if (connectableProtocols.length > 1) {
        return ProtocolResolution(
          selected: selected,
          effective: requested,
          backendProtocol: requested,
          warning: 'Automatic selected ${vpnProtocolLabel(requested)} based on '
              'local runtime and backend availability.',
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
        runtimeBlocked: true,
        error: _unsupportedProtocolMessage(requested, capabilities),
      );
    }
    if (catalog != null && !backendAvailableProtocols.contains(requested)) {
      return ProtocolResolution(
        selected: selected,
        effective: requested,
        backendProtocol: requested,
        backendBlocked: true,
        error: _backendUnavailableMessage(requested, catalog.entryFor(requested)),
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

  String _backendUnavailableMessage(
    VpnProtocol protocol,
    VpnProtocolCatalogEntry? entry,
  ) {
    final reason = entry?.reason?.trim().toLowerCase();
    if (reason == 'disabled_server_side') {
      return '${vpnProtocolLabel(protocol)} is disabled on the backend.';
    }
    if (reason == 'restricted_by_plan') {
      return '${vpnProtocolLabel(protocol)} is not included in your plan.';
    }
    if (reason == 'not_supported_on_platform') {
      return '${vpnProtocolLabel(protocol)} is not supported for this device.';
    }
    if (reason == 'no_active_server_support' ||
        reason == 'unavailable_region') {
      return 'No active server currently supports ${vpnProtocolLabel(protocol)}.';
    }
    if (reason == 'protocol_temporarily_unavailable') {
      return '${vpnProtocolLabel(protocol)} is temporarily unavailable.';
    }
    if (reason == 'openvpn_server_misconfigured' ||
        reason == 'ikev2_server_misconfigured') {
      return '${vpnProtocolLabel(protocol)} is not provisioned correctly on the server.';
    }
    if (reason == 'openvpn_healthcheck_fail' ||
        reason == 'ikev2_healthcheck_fail') {
      return '${vpnProtocolLabel(protocol)} is currently failing server health checks.';
    }
    if (reason == 'ikev2_auth_mode_mismatch_linux') {
      return 'IKEv2 is not configured with a Linux-compatible auth mode.';
    }
    return '${vpnProtocolLabel(protocol)} is unavailable on the backend for '
        'this device, plan, or server.';
  }
}
