import 'dart:async';

import 'vpn_service.dart';

enum VpnHealthFailureType {
  noTunnel,
  noRoute,
  trafficBlocked,
  highLatency,
  packetLoss,
  dnsLeak,
  partialConnectivity,
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

  bool get isDegraded =>
      type == VpnHealthFailureType.highLatency ||
      type == VpnHealthFailureType.packetLoss ||
      type == VpnHealthFailureType.partialConnectivity;
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
    this.degradedFailureThreshold = 2,
    this.unhealthyFailureThreshold = 1,
  })  : _sample = sample,
        _onIssue = onIssue;

  final VpnHealthSampler _sample;
  final VpnHealthIssueHandler _onIssue;
  final VpnHealthRecoveredHandler? onRecovered;
  final Duration interval;
  final int degradedFailureThreshold;
  final int unhealthyFailureThreshold;

  Timer? _timer;
  bool _running = false;
  bool _pollInFlight = false;
  VpnHealthFailureType? _lastFailureType;
  int _failureCount = 0;
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
    _lastFailureType = null;
    _failureCount = 0;
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
        if (_reportedDegraded && onRecovered != null) {
          await onRecovered!(snapshot);
        }
        _reportedDegraded = false;
        return;
      }

      if (issue.isDegraded) {
        _reportedDegraded = true;
      }
      await _onIssue(issue);
    } finally {
      _pollInFlight = false;
    }
  }

  VpnHealthIssue? _classifyIssue(VpnHealthSnapshot snapshot) {
    final failureType = _mapFailureType(snapshot);
    if (failureType == null) {
      _lastFailureType = null;
      _failureCount = 0;
      return null;
    }

    if (_lastFailureType == failureType) {
      _failureCount += 1;
    } else {
      _lastFailureType = failureType;
      _failureCount = 1;
    }

    final threshold = _isDegradedFailure(failureType)
        ? degradedFailureThreshold
        : unhealthyFailureThreshold;
    if (_failureCount < threshold) {
      return null;
    }

    return VpnHealthIssue(
      type: failureType,
      snapshot: snapshot,
      reason: _failureReason(snapshot, failureType),
      consecutiveFailures: _failureCount,
    );
  }

  static bool _isDegradedFailure(VpnHealthFailureType type) {
    return type == VpnHealthFailureType.highLatency ||
        type == VpnHealthFailureType.packetLoss ||
        type == VpnHealthFailureType.partialConnectivity;
  }

  static VpnHealthFailureType? _mapFailureType(VpnHealthSnapshot snapshot) {
    return switch (snapshot.failureType) {
      VpnValidationFailureType.noTunnel => VpnHealthFailureType.noTunnel,
      VpnValidationFailureType.noRoute => VpnHealthFailureType.noRoute,
      VpnValidationFailureType.trafficBlocked =>
        VpnHealthFailureType.trafficBlocked,
      VpnValidationFailureType.highLatency =>
        VpnHealthFailureType.highLatency,
      VpnValidationFailureType.packetLoss => VpnHealthFailureType.packetLoss,
      VpnValidationFailureType.dnsLeak => VpnHealthFailureType.dnsLeak,
      VpnValidationFailureType.partialConnectivity =>
        VpnHealthFailureType.partialConnectivity,
      null => snapshot.validationStatus == VpnValidationStatus.unhealthy
          ? VpnHealthFailureType.trafficBlocked
          : snapshot.validationStatus == VpnValidationStatus.degraded
              ? VpnHealthFailureType.partialConnectivity
              : null,
    };
  }

  static String _failureReason(
    VpnHealthSnapshot snapshot,
    VpnHealthFailureType type,
  ) {
    switch (type) {
      case VpnHealthFailureType.noTunnel:
        return 'VPN interface is no longer up.';
      case VpnHealthFailureType.noRoute:
        return 'VPN policy routing is no longer installed.';
      case VpnHealthFailureType.trafficBlocked:
        return 'Tunnel traffic probes failed over both ICMP and HTTPS.';
      case VpnHealthFailureType.highLatency:
        return 'Tunnel latency is elevated (${snapshot.latencyMs ?? -1}ms).';
      case VpnHealthFailureType.packetLoss:
        return 'Tunnel packet loss reached ${(snapshot.packetLoss * 100).toStringAsFixed(0)}%.';
      case VpnHealthFailureType.dnsLeak:
        return 'Tunnel DNS path is not isolated to the VPN interface.';
      case VpnHealthFailureType.partialConnectivity:
        return 'Tunnel connectivity is only partially available.';
    }
  }
}
