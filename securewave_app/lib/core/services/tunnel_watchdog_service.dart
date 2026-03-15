import 'dart:async';

import '../models/vpn_status.dart';
import 'vpn_service.dart';

enum TunnelWatchdogIssueType {
  handshakeFailure,
  serverDisconnect,
  interfaceRemoved,
}

class TunnelWatchdogIssue {
  const TunnelWatchdogIssue({
    required this.type,
    required this.snapshot,
    required this.reason,
  });

  final TunnelWatchdogIssueType type;
  final VpnRuntimeSnapshot snapshot;
  final String reason;
}

typedef TunnelWatchdogSampler = Future<VpnRuntimeSnapshot?> Function();
typedef TunnelWatchdogIssueHandler = Future<void> Function(
  TunnelWatchdogIssue issue,
);

class TunnelWatchdogService {
  TunnelWatchdogService({
    required TunnelWatchdogSampler sample,
    required TunnelWatchdogIssueHandler onIssue,
    this.interval = const Duration(seconds: 3),
    this.handshakeFailureThreshold = 2,
    this.serverDisconnectThreshold = 2,
    this.interfaceRemovalThreshold = 2,
  })  : _sample = sample,
        _onIssue = onIssue;

  final TunnelWatchdogSampler _sample;
  final TunnelWatchdogIssueHandler _onIssue;
  final Duration interval;
  final int handshakeFailureThreshold;
  final int serverDisconnectThreshold;
  final int interfaceRemovalThreshold;

  Timer? _timer;
  bool _running = false;
  bool _pollInFlight = false;
  int _handshakeFailures = 0;
  int _serverDisconnects = 0;
  int _interfaceRemovals = 0;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _resetCounters();
    await _poll();
    if (!_running) return;
    _timer = Timer.periodic(interval, (_) {
      unawaited(_poll());
    });
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _resetCounters();
  }

  void _resetCounters() {
    _handshakeFailures = 0;
    _serverDisconnects = 0;
    _interfaceRemovals = 0;
  }

  Future<void> _poll() async {
    if (!_running || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final snapshot = await _sample();
      if (!_running || snapshot == null) return;

      final issue = _classifyIssue(snapshot);
      if (issue == null) {
        return;
      }

      await _onIssue(issue);
      _resetCounters();
    } finally {
      _pollInFlight = false;
    }
  }

  TunnelWatchdogIssue? _classifyIssue(VpnRuntimeSnapshot snapshot) {
    if (snapshot.nativeStatus != VpnStatus.connected) {
      _serverDisconnects += 1;
      _handshakeFailures = 0;
      _interfaceRemovals = 0;
      if (_serverDisconnects < serverDisconnectThreshold) {
        return null;
      }
      return TunnelWatchdogIssue(
        type: TunnelWatchdogIssueType.serverDisconnect,
        snapshot: snapshot,
        reason:
            'Native runtime reported ${snapshot.nativeStatus.name} while the app expected an active tunnel.',
      );
    }

    _serverDisconnects = 0;

    if (!snapshot.hasNativeTrafficStats || !snapshot.sampleAvailable) {
      _handshakeFailures = 0;
      _interfaceRemovals = 0;
      return null;
    }

    if (!snapshot.interfaceCompatible ||
        (snapshot.trafficConnected &&
            (snapshot.interfaceName?.trim().isEmpty ?? true))) {
      _interfaceRemovals += 1;
      _handshakeFailures = 0;
      if (_interfaceRemovals < interfaceRemovalThreshold) {
        return null;
      }
      return TunnelWatchdogIssue(
        type: TunnelWatchdogIssueType.interfaceRemoved,
        snapshot: snapshot,
        reason:
            'WireGuard interface is missing or no longer matches the expected tunnel.',
      );
    }

    _interfaceRemovals = 0;

    if (!snapshot.trafficConnected) {
      _handshakeFailures += 1;
      if (_handshakeFailures < handshakeFailureThreshold) {
        return null;
      }
      return TunnelWatchdogIssue(
        type: TunnelWatchdogIssueType.handshakeFailure,
        snapshot: snapshot,
        reason:
            'Tunnel runtime stayed connected but native traffic stats no longer reported an established data path.',
      );
    }

    _handshakeFailures = 0;
    return null;
  }
}
