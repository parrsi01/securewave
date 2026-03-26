import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';
import 'vpn_service.dart';

// ── Log entry model ───────────────────────────────────────────────────────────

class HealthLogEntry {
  const HealthLogEntry({
    required this.timestamp,
    required this.validationStatus,
    required this.validationScore,
    required this.failureType,
    required this.latencyMs,
    required this.packetLoss,
  });

  final DateTime timestamp;
  final VpnValidationStatus validationStatus;
  final int validationScore;
  final VpnValidationFailureType? failureType;
  final int? latencyMs;
  final double packetLoss;

  Map<String, Object?> toJson() => {
        'ts': timestamp.toIso8601String(),
        'status': validationStatus.name,
        'score': validationScore,
        'failure_type': failureType?.name,
        'latency_ms': latencyMs,
        'packet_loss': packetLoss,
      };

  factory HealthLogEntry.fromJson(Map<String, dynamic> json) {
    return HealthLogEntry(
      timestamp: DateTime.parse(json['ts'] as String),
      validationStatus: VpnValidationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => VpnValidationStatus.healthy,
      ),
      validationScore: (json['score'] as num).toInt(),
      failureType: json['failure_type'] == null
          ? null
          : VpnValidationFailureType.values.firstWhere(
              (f) => f.name == json['failure_type'],
              orElse: () => VpnValidationFailureType.partialConnectivity,
            ),
      latencyMs: json['latency_ms'] == null
          ? null
          : (json['latency_ms'] as num).toInt(),
      packetLoss: (json['packet_loss'] as num).toDouble(),
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Appends health snapshots to a local JSONL file with size-based rotation.
///
/// File location: `<app support dir>/health_log.jsonl`
/// Rotation: when the file exceeds [maxFileSizeBytes], the file is truncated
/// to the newest [keepLines] lines. This is safe for async writes.
class HealthLogService {
  HealthLogService({
    this.maxFileSizeBytes = 512 * 1024, // 512 KB
    this.keepLines = 500,
    this.overrideDirectory,
  });

  final int maxFileSizeBytes;
  final int keepLines;

  /// Override the storage directory. Intended for testing only.
  final String? overrideDirectory;

  static const String _fileName = 'health_log.jsonl';
  static const String _tag = 'SecureWave.HealthLog';

  File? _logFile;
  bool _initialized = false;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> append(HealthLogEntry entry) async {
    try {
      final file = await _getFile();
      final line = jsonEncode(entry.toJson());
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      await _rotateIfNeeded(file);
    } catch (error, stackTrace) {
      AppLogger.error(
        'HealthLogService: append failed',
        error: error,
        stackTrace: stackTrace,
        tag: _tag,
      );
    }
  }

  /// Read the last [count] entries from the log file.
  ///
  /// Returns an empty list if the file does not exist or is unreadable.
  Future<List<HealthLogEntry>> readRecent({int count = 50}) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return const [];
      final lines = await file.readAsLines();
      final tail = lines.length <= count
          ? lines
          : lines.sublist(lines.length - count);
      final entries = <HealthLogEntry>[];
      for (final line in tail) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(HealthLogEntry.fromJson(
              jsonDecode(line) as Map<String, dynamic>));
        } catch (error, stackTrace) {
          AppLogger.error(
            'HealthLogService: skipping malformed line',
            error: error,
            stackTrace: stackTrace,
            tag: _tag,
          );
        }
      }
      return entries;
    } catch (error, stackTrace) {
      AppLogger.error(
        'HealthLogService: readRecent failed',
        error: error,
        stackTrace: stackTrace,
        tag: _tag,
      );
      return const [];
    }
  }

  /// Delete the log file. Used for test teardown or user-initiated clear.
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
      _initialized = false;
      _logFile = null;
    } catch (error, stackTrace) {
      AppLogger.error(
        'HealthLogService: clear failed',
        error: error,
        stackTrace: stackTrace,
        tag: _tag,
      );
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<File> _getFile() async {
    if (_initialized && _logFile != null) return _logFile!;
    final dirPath = overrideDirectory ??
        (await getApplicationSupportDirectory()).path;
    _logFile = File('$dirPath/$_fileName');
    _initialized = true;
    return _logFile!;
  }

  Future<void> _rotateIfNeeded(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size <= maxFileSizeBytes) return;

      AppLogger.info(
        '[HEALTH_LOG] rotating size=${stat.size}',
        tag: _tag,
      );

      final lines = await file.readAsLines();
      if (lines.length <= keepLines) return;

      final kept = lines.sublist(lines.length - keepLines);
      await file.writeAsString('${kept.join('\n')}\n', flush: true);
    } catch (error, stackTrace) {
      AppLogger.error(
        'HealthLogService: rotation failed',
        error: error,
        stackTrace: stackTrace,
        tag: _tag,
      );
    }
  }
}
