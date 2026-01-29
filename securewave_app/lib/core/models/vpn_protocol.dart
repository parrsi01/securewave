enum VpnProtocol {
  wireGuard,
  openVpn,
  ikev2,
}

String vpnProtocolLabel(VpnProtocol protocol) {
  switch (protocol) {
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
