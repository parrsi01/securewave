enum VpnStatus {
  disconnected,
  connecting,
  disconnecting,
  connected,
  error,
}

/// Sub-phase of the connect flow, set only while [VpnStatus.connecting].
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
