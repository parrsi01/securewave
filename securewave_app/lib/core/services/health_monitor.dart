import 'dart:async';

import 'vpn_service.dart';

enum VpnHealthFailureType {
  softFailure,
  hardFailure,
  handshakeFailure,
}

class VpnHealthIssue {
  const VpnHealthIssue({
    required this.type,
    required this.snapshot,
    required this.reason,
    required this.consecutiveFailures,
  });

  final VpnHealthFailureType type;
  final VpnHealthSnapshot snapshot;
  final String reason;
  final int consecutiveFailures;
}

typedef VpnHealthSampler = Future<VpnHealthSnapshot?> Function();
typedef VpnHealthIssueHandler = Future<void> Function(VpnHealthIssue issue);
typedef VpnHealthRecoveredHandler = Future<void> Function(
    VpnHealthSnapshot snapshot);

class HealthMonitorService {
  HealthMonitorService({
    required VpnHealthSampler sample,
    required VpnHealthIssueHandler onIssue,
    this.onRecovered,
    this.interval = const Duration(seconds: 3),
    this.softFailureThreshold = 2,
    this.hardFailureThreshold = 1,
    this.handshakeFailureThreshold = 1,
  })  : _sample = sample,
        _onIssue = onIssue;

  final VpnHealthSampler _sample;
  final VpnHealthIssueHandler _onIssue;
  final VpnHealthRecoveredHandler? onRecovered;
  final Duration interval;
  final int softFailureThreshold;
  final int hardFailureThreshold;
  final int handshakeFailureThreshold;

  Timer? _timer;
  bool _running = false;
  bool _pollInFlight = false;
  int _softFailures = 0;
  int _hardFailures = 0;
  int _handshakeFailures = 0;
  bool _reportedDegraded = false;

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
    _softFailures = 0;
    _hardFailures = 0;
    _handshakeFailures = 0;
    _reportedDegraded = false;
  }

  Future<void> _poll() async {
    if (!_running || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final snapshot = await _sample();
      if (!_running || snapshot == null) return;

      final issue = _classifyIssue(snapshot);
      if (issue == null) {
        final healthy =
            _softFailures == 0 && _hardFailures == 0 && _handshakeFailures == 0;
        if (healthy && _reportedDegraded && onRecovered != null) {
          await onRecovered!(snapshot);
        }
        if (healthy) {
          _reportedDegraded = false;
        }
        return;
      }

      if (issue.type == VpnHealthFailureType.softFailure) {
        _reportedDegraded = true;
      }
      await _onIssue(issue);
    } finally {
      _pollInFlight = false;
    }
  }

  VpnHealthIssue? _classifyIssue(VpnHealthSnapshot snapshot) {
    if (!snapshot.interfaceUp ||
        !snapshot.routePresent ||
        !snapshot.policyRoutingPresent) {
      _hardFailures += 1;
      _softFailures = 0;
      _handshakeFailures = 0;
      if (_hardFailures < hardFailureThreshold) {
        return null;
      }
      return VpnHealthIssue(
        type: VpnHealthFailureType.hardFailure,
        snapshot: snapshot,
        reason: !snapshot.interfaceUp
            ? 'VPN interface is no longer up.'
            : !snapshot.policyRoutingPresent
                ? 'WireGuard policy routing is no longer installed.'
                : 'VPN route is no longer installed.',
        consecutiveFailures: _hardFailures,
      );
    }

    _hardFailures = 0;

    if (!snapshot.handshakeRecent) {
      _handshakeFailures += 1;
      _softFailures = 0;
      if (_handshakeFailures < handshakeFailureThreshold) {
        return null;
      }
      return VpnHealthIssue(
        type: VpnHealthFailureType.handshakeFailure,
        snapshot: snapshot,
        reason: snapshot.handshakeAgeSeconds == null ||
                snapshot.handshakeAgeSeconds! < 0
            ? 'WireGuard handshake is missing.'
            : 'WireGuard handshake is stale (${snapshot.handshakeAgeSeconds}s).',
        consecutiveFailures: _handshakeFailures,
      );
    }

    _handshakeFailures = 0;

    if (!snapshot.pingReachable) {
      _softFailures += 1;
      if (_softFailures < softFailureThreshold) {
        return null;
      }
      return VpnHealthIssue(
        type: VpnHealthFailureType.softFailure,
        snapshot: snapshot,
        reason:
            'Health probe via ${snapshot.interfaceName ?? "vpn"} lost reachability while the tunnel remained up.',
        consecutiveFailures: _softFailures,
      );
    }

    _softFailures = 0;
    return null;
  }
}
