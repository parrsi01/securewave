import '../models/vpn_status.dart';

enum VpnTransitionTrigger {
  initSync,
  protocolLoaded,
  userConnectRequested,
  userDisconnectRequested,
  autoReconnectRequested,
  connectOperationStarted,
  connectOperationCancelled,
  connectOperationSucceeded,
  connectOperationFailed,
  disconnectOperationStarted,
  disconnectOperationSucceeded,
  disconnectOperationFailed,
  connectivityLost,
  connectivityRestored,
  timeout,
  dispose,
}

class VpnStateMachineConfig {
  const VpnStateMachineConfig({
    this.connectTimeout = const Duration(seconds: 25),
    this.disconnectTimeout = const Duration(seconds: 20),
    this.profileFetchTimeout = const Duration(seconds: 15),
    this.connectOperationGuardTimeout = const Duration(seconds: 45),
    this.disconnectOperationGuardTimeout = const Duration(seconds: 30),
    this.autoReconnectCooldown = const Duration(seconds: 10),
    this.transitionHistoryLimit = 200,
    this.maxReconcileIterations = 64,
    this.autoConnectInitDelay = const Duration(milliseconds: 400),
  });

  final Duration connectTimeout;
  final Duration disconnectTimeout;
  final Duration profileFetchTimeout;
  final Duration connectOperationGuardTimeout;
  final Duration disconnectOperationGuardTimeout;
  final Duration autoReconnectCooldown;
  final int transitionHistoryLimit;
  final int maxReconcileIterations;
  final Duration autoConnectInitDelay;
}

class VpnTransitionRecord {
  const VpnTransitionRecord({
    required this.from,
    required this.to,
    required this.trigger,
    required this.at,
    required this.operationId,
  });

  final VpnStatus from;
  final VpnStatus to;
  final VpnTransitionTrigger trigger;
  final DateTime at;
  final int operationId;
}

class VpnStateMachine {
  static const Map<VpnStatus, Set<VpnStatus>> _allowedTransitions = {
    VpnStatus.disconnected: {
      VpnStatus.connecting,
      VpnStatus.error,
    },
    VpnStatus.connecting: {
      VpnStatus.connected,
      VpnStatus.disconnecting,
      VpnStatus.disconnected,
      VpnStatus.error,
    },
    VpnStatus.connected: {
      VpnStatus.disconnecting,
      VpnStatus.error,
    },
    VpnStatus.disconnecting: {
      VpnStatus.disconnected,
      VpnStatus.connecting,
      VpnStatus.error,
    },
    VpnStatus.error: {
      VpnStatus.connecting,
      VpnStatus.disconnecting,
      VpnStatus.disconnected,
    },
  };

  static bool canTransition(VpnStatus from, VpnStatus to) {
    if (from == to) return true;
    final allowed = _allowedTransitions[from];
    return allowed?.contains(to) ?? false;
  }

  static Map<VpnStatus, Set<VpnStatus>> transitionMap() {
    return _allowedTransitions.map(
      (key, value) => MapEntry(key, Set<VpnStatus>.from(value)),
    );
  }
}
