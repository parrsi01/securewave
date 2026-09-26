enum VpnProtocol {
  wireGuard,
}

String vpnProtocolLabel(VpnProtocol protocol) {
  switch (protocol) {
    case VpnProtocol.wireGuard:
      return 'WireGuard';
  }
}

String vpnProtocolStorageValue(VpnProtocol protocol) {
  switch (protocol) {
    case VpnProtocol.wireGuard:
      return 'wireguard';
  }
}

VpnProtocol vpnProtocolFromStorage(String? value) => VpnProtocol.wireGuard;
