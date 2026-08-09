enum VpnProtocol {
  wireGuard,
}

String vpnProtocolLabel(VpnProtocol protocol) => switch (protocol) {
      VpnProtocol.wireGuard => 'WireGuard',
    };

String vpnProtocolStorageValue(VpnProtocol protocol) => switch (protocol) {
      VpnProtocol.wireGuard => 'wireguard',
    };
