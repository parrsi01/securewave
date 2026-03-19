import '../models/vpn_status.dart';

enum VpnTransitionTrigger {
  initSync,
  protocolLoaded,
  userConnectRequested,
  userDisconnectRequested,
  autoReconnectRequested,
  reconnectBackoffElapsed,
  connectOperationStarted,
  connectOperationCancelled,
  connectOperationSucceeded,
  connectVerificationStarted,
  connectVerificationSucceeded,
  connectOperationFailed,
  disconnectOperationStarted,
  disconnectOperationSucceeded,
  disconnectOperationFailed,
  connectivityLost,
  connectivityRestored,
  networkPathChanged,
  healthMonitorDegraded,
  healthMonitorRecovered,
  healthMonitorRecoveryRequested,
  watchdogRecoveryRequested,
  watchdogFailureDetected,
  shutdownRequested,
  timeout,
  dispose,
}

class VpnStateMachineConfig {
  const VpnStateMachineConfig({
    // Linux native bring-up allows up to 30s in the runner while wg-quick
    // completes and PostUp hooks settle. Keep the state-machine timeout above
    // that native budget so we surface the native result instead of timing out
    // first in Dart.
    this.connectTimeout = const Duration(seconds: 40),
    this.disconnectTimeout = const Duration(seconds: 20),
    this.profileFetchTimeout = const Duration(seconds: 15),
    this.connectOperationGuardTimeout = const Duration(seconds: 45),
    this.disconnectOperationGuardTimeout = const Duration(seconds: 30),
    this.autoReconnectCooldown = const Duration(seconds: 10),
    this.reconnectDelayAfterDisconnect = const Duration(seconds: 5),
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
  final Duration reconnectDelayAfterDisconnect;
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
      VpnStatus.reconnecting,
      VpnStatus.error,
    },
    VpnStatus.connecting: {
      VpnStatus.verifying,
      VpnStatus.connected,
      VpnStatus.reconnecting,
      VpnStatus.disconnected,
      VpnStatus.error,
    },
    VpnStatus.verifying: {
      VpnStatus.connected,
      VpnStatus.reconnecting,
      VpnStatus.disconnecting,
      VpnStatus.disconnected,
      VpnStatus.error,
    },
    VpnStatus.reconnecting: {
      VpnStatus.connecting,
      VpnStatus.verifying,
      VpnStatus.connected,
      VpnStatus.disconnecting,
      VpnStatus.disconnected,
      VpnStatus.error,
    },
    VpnStatus.degraded: {
      VpnStatus.connected,
      VpnStatus.reconnecting,
      VpnStatus.disconnecting,
      VpnStatus.error,
    },
    VpnStatus.disconnecting: {
      VpnStatus.disconnected,
      VpnStatus.reconnecting,
      VpnStatus.error,
    },
    VpnStatus.connected: {
      VpnStatus.degraded,
      VpnStatus.reconnecting,
      VpnStatus.disconnecting,
      VpnStatus.error,
    },
    VpnStatus.error: {
      VpnStatus.disconnected,
      VpnStatus.reconnecting,
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
