enum VpnStatus {
  disconnected,
  connecting,
  verifying,
  reconnecting,
  degraded,
  disconnecting,
  connected,
  error,
}

/// Sub-phase of the connect flow, set while [VpnStatus.connecting] or
/// [VpnStatus.reconnecting].
enum ConnectPhase {
  /// Verifying user session / auth token.
  authenticating,

  /// Reaching backend health endpoint.
  checkingBackend,

  /// Resolving protocol + server catalog.
  resolvingProtocol,

  /// Fetching WireGuard/OpenVPN/IKEv2 profile from backend.
  fetchingProfile,

  /// Handing profile to native runtime, waiting for handshake.
  establishingTunnel,

  /// Tunnel is up, verifying data-plane (exit IP, DNS).
  verifyingConnection,
}
