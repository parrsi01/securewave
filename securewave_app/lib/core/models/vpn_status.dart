enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  reconnecting,
  error,
}

enum VpnConnectionStage {
  idle,
  login,
  fetchServers,
  fetchProfile,
  protocolReady,
  tunnelStart,
  tunnelActive,
}
