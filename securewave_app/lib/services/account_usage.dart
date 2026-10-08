import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

/// Decimal units match the server's 5,000,000,000-byte allowance.
String formatDataBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(2)} KB';
  if (bytes < 1000000000) return '${(bytes / 1000000).toStringAsFixed(2)} MB';
  return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
}

class SavedUsageSession {
  SavedUsageSession.fromJson(Map<String, dynamic> data)
      : id = data['session_id'] as int,
        sent = data['bytes_sent'] as int,
        received = data['bytes_received'] as int,
        finished = data['disconnected_at'] != null,
        quality = data['recording_quality'] as String;
  final int id, sent, received;
  final bool finished;
  final String quality;
  int get total => sent + received;
}

class MonthlyAccountUsage {
  MonthlyAccountUsage.fromJson(Map<String, dynamic> data)
      : userId = data['user_id'] as int,
        email = data['email'] as String,
        planName = data['plan_name'] as String,
        planId = data['plan_id'] as String,
        usedBytes = data['used_bytes'] as int,
        quotaBytes = data['quota_bytes'] as int?,
        periodStart = DateTime.parse(data['period_start'] as String).toUtc(),
        periodEnd = DateTime.parse(data['period_end'] as String).toUtc(),
        lastSession = data['last_session'] == null
            ? null
            : SavedUsageSession.fromJson(
                Map<String, dynamic>.from(data['last_session'] as Map)),
        tracked = {
          for (final entry in data['tracked_sessions'] as List)
            entry['session_id'] as int: SavedUsageSession.fromJson(
                Map<String, dynamic>.from(entry as Map))
        } {
    if (userId <= 0 ||
        usedBytes < 0 ||
        (quotaBytes != null && quotaBytes! <= 0)) {
      throw const FormatException('Invalid account usage response');
    }
  }
  final int userId, usedBytes;
  final int? quotaBytes;
  final String email, planName, planId;
  final DateTime periodStart, periodEnd;
  final SavedUsageSession? lastSession;
  final Map<int, SavedUsageSession> tracked;
}

class _Observation {
  _Observation(this.sent, this.received, this.period, {this.finalized = false});
  final int sent, received;
  final DateTime period;
  final bool finalized;
}

/// Server totals plus only the unacknowledged part of account-owned sessions.
/// The native reporter owns durable billing; this store never submits traffic.
class AccountUsageStore extends ChangeNotifier {
  AccountUsageStore(this.api,
      {FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;
  final ApiService api;
  final FlutterSecureStorage _storage;
  final _observations = <int, _Observation>{};
  MonthlyAccountUsage? summary;
  String? notice;
  bool loading = true;
  bool _disposed = false;
  bool _refreshing = false;
  int? _owner;
  String get _key => 'monthly_usage_pending_v1_$_owner';

  int get pendingBytes {
    final account = summary;
    if (account == null) return 0;
    var total = 0;
    for (final item in _observations.entries) {
      if (item.value.period != account.periodStart) continue;
      final saved = account.tracked[item.key] ??
          (account.lastSession?.id == item.key ? account.lastSession : null);
      if (saved == null) continue;
      total += math.max(0, item.value.sent - saved.sent) +
          math.max(0, item.value.received - saved.received);
    }
    return total;
  }

  int? get usedBytes =>
      summary == null ? null : summary!.usedBytes + pendingBytes;
  bool get limitReached =>
      summary?.quotaBytes != null && usedBytes! >= summary!.quotaBytes!;
  String? get syncNotice =>
      notice ?? (pendingBytes > 0 ? 'Saving latest measured usage…' : null);

  Future<void> initialize() async {
    try {
      final first = await api.fetchMonthlyUsage();
      if (_disposed) return;
      _owner = first.userId;
      summary = first;
      final raw = await _storage.read(key: _key);
      if (_disposed) return;
      if (raw != null) {
        try {
          final entries = jsonDecode(raw) as List;
          for (final entry in entries) {
            final period = DateTime.parse(entry['period'] as String).toUtc();
            if (period != first.periodStart) continue;
            _observations[entry['id'] as int] = _Observation(
                entry['sent'] as int, entry['received'] as int, period,
                finalized: true);
          }
        } catch (_) {
          await _storage.delete(key: _key);
        }
      }
      notice = null;
      if (_observations.isNotEmpty) await refresh();
    } catch (_) {
      notice = 'Monthly usage is unavailable. Retry when you are online.';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    if (_owner == null) return initialize();
    _refreshing = true;
    try {
      final next =
          await api.fetchMonthlyUsage(sessionIds: _observations.keys.toList());
      if (_disposed) return;
      if (next.userId != _owner) throw const FormatException('Account changed');
      summary = next;
      _observations.removeWhere((id, observation) {
        final saved = next.tracked[id];
        return observation.period != next.periodStart ||
            saved == null ||
            (observation.finalized &&
                saved.finished &&
                saved.sent >= observation.sent &&
                saved.received >= observation.received);
      });
      notice = null;
      await _persist();
    } catch (_) {
      if (!_disposed) {
        notice = 'Showing saved usage. Updates will retry automatically.';
      }
    } finally {
      _refreshing = false;
      _changed();
    }
  }

  Future<void> observe(int sessionId, int sent, int received,
      {bool finalized = false}) async {
    final account = summary;
    if (account == null || _disposed) return;
    // Session IDs originate in an authenticated start response and are checked
    // again by the monthly endpoint before contributing to the display.
    _observations[sessionId] =
        _Observation(sent, received, account.periodStart, finalized: finalized);
    _changed();
    if (finalized) await _persist();
  }

  Future<void> _persist() async {
    if (_owner == null || _disposed) return;
    try {
      await _storage.write(
          key: _key,
          value: jsonEncode([
            for (final item in _observations.entries)
              if (item.value.finalized)
                {
                  'id': item.key,
                  'sent': item.value.sent,
                  'received': item.value.received,
                  'period': item.value.period.toIso8601String()
                }
          ]));
    } catch (_) {
      // UI caching failure cannot stop Connect/Disconnect. The privileged
      // recorder still journals and retries the authoritative final bytes.
      notice =
          'Local usage preview could not be cached. Server recording continues.';
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
