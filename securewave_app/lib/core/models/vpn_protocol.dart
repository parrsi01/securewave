enum VpnProtocol {
  auto,
  wireGuard,
  openVpn,
  ikev2,
}

String vpnProtocolLabel(VpnProtocol protocol) {
  switch (protocol) {
    case VpnProtocol.auto:
      return 'Auto';
    case VpnProtocol.wireGuard:
      return 'WireGuard';
    case VpnProtocol.openVpn:
      return 'OpenVPN';
    case VpnProtocol.ikev2:
      return 'IKEv2/IPSec';
  }
}

String vpnProtocolStorageValue(VpnProtocol protocol) {
  switch (protocol) {
    case VpnProtocol.auto:
      return 'auto';
    case VpnProtocol.wireGuard:
      return 'wireguard';
    case VpnProtocol.openVpn:
      return 'openvpn';
    case VpnProtocol.ikev2:
      return 'ikev2';
  }
}

VpnProtocol vpnProtocolFromStorage(String? value) {
  switch (value?.toLowerCase()) {
    case 'auto':
      return VpnProtocol.auto;
    case 'openvpn':
      return VpnProtocol.openVpn;
    case 'ikev2':
    case 'ipsec':
    case 'ikev2/ipsec':
      return VpnProtocol.ikev2;
    case 'wireguard':
    default:
      return VpnProtocol.wireGuard;
  }
}

const List<VpnProtocol> vpnProtocolPriority = <VpnProtocol>[
  VpnProtocol.wireGuard,
  VpnProtocol.ikev2,
  VpnProtocol.openVpn,
];
