enum VpnReadinessGateState {
  unknown,
  ready,
  notReady,
}

class VpnReadiness {
  const VpnReadiness({
    this.backendReachable = VpnReadinessGateState.unknown,
    this.authenticated = VpnReadinessGateState.unknown,
    this.serverCatalogReady = VpnReadinessGateState.unknown,
    this.profileReady = VpnReadinessGateState.unknown,
    this.runtimeReady = VpnReadinessGateState.unknown,
    this.tunnelUp = VpnReadinessGateState.unknown,
    this.backendProtocolDisabled = false,
    this.runtimeHint,
    this.lastErrorCode,
  });

  final VpnReadinessGateState backendReachable;
  final VpnReadinessGateState authenticated;
  final VpnReadinessGateState serverCatalogReady;
  final VpnReadinessGateState profileReady;
  final VpnReadinessGateState runtimeReady;
  final VpnReadinessGateState tunnelUp;
  final bool backendProtocolDisabled;
  final String? runtimeHint;
  final String? lastErrorCode;

  bool get isRuntimeBlocked => runtimeReady == VpnReadinessGateState.notReady;

  VpnReadiness copyWith({
    VpnReadinessGateState? backendReachable,
    VpnReadinessGateState? authenticated,
    VpnReadinessGateState? serverCatalogReady,
    VpnReadinessGateState? profileReady,
    VpnReadinessGateState? runtimeReady,
    VpnReadinessGateState? tunnelUp,
    bool? backendProtocolDisabled,
    String? runtimeHint,
    String? lastErrorCode,
    bool clearRuntimeHint = false,
    bool clearLastErrorCode = false,
  }) {
    return VpnReadiness(
      backendReachable: backendReachable ?? this.backendReachable,
      authenticated: authenticated ?? this.authenticated,
      serverCatalogReady: serverCatalogReady ?? this.serverCatalogReady,
      profileReady: profileReady ?? this.profileReady,
      runtimeReady: runtimeReady ?? this.runtimeReady,
      tunnelUp: tunnelUp ?? this.tunnelUp,
      backendProtocolDisabled:
          backendProtocolDisabled ?? this.backendProtocolDisabled,
      runtimeHint: clearRuntimeHint ? null : (runtimeHint ?? this.runtimeHint),
      lastErrorCode:
          clearLastErrorCode ? null : (lastErrorCode ?? this.lastErrorCode),
    );
  }
}
