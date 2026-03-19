import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLogEntry {
  AppLogEntry(this.message, {required this.level, required this.timestamp});

  final String message;
  final int level;
  final DateTime timestamp;

  @override
  String toString() => '[${timestamp.toIso8601String()}] $message';
}

class AppErrorEntry {
  AppErrorEntry({required this.message, this.error, this.stackTrace});

  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

class AppLogger {
  static const bool _debugLoggingEnabled = !kReleaseMode;
  static const bool _retainLogsInMemory = !kReleaseMode;

  static final ValueNotifier<List<AppLogEntry>> logStream =
      ValueNotifier<List<AppLogEntry>>(<AppLogEntry>[]);
  static final ValueNotifier<AppErrorEntry?> errorStream =
      ValueNotifier<AppErrorEntry?>(null);

  static void info(String message, {String tag = 'SecureWave'}) {
    if (!_debugLoggingEnabled) return;
    _record(message, level: 500, tag: tag);
  }

  static void debug(String message, {String tag = 'SecureWave'}) {
    if (!_debugLoggingEnabled) return;
    _record(message, level: 500, tag: tag);
  }

  static void warning(String message, {String tag = 'SecureWave'}) {
    _record(message, level: 900, tag: tag);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'SecureWave',
  }) {
    _record(message,
        level: 1000, tag: tag, error: error, stackTrace: stackTrace);
    errorStream.value =
        AppErrorEntry(message: message, error: error, stackTrace: stackTrace);
  }

  static void captureFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    error(
      'Flutter error: ${details.exceptionAsString()}',
      error: details.exception,
      stackTrace: details.stack,
    );
  }

  static bool capturePlatformError(Object error, StackTrace stackTrace) {
    AppLogger.error('Platform error', error: error, stackTrace: stackTrace);
    return true;
  }

  static void vpn(
    String category,
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
    int level = 500,
  }) {
    final normalizedCategory = category.trim().toUpperCase();
    final normalizedEvent = event.trim().toUpperCase();
    final suffix = _formatFields(fields);
    final message = suffix.isEmpty
        ? '[VPN][$normalizedCategory] $normalizedEvent'
        : '[VPN][$normalizedCategory] $normalizedEvent $suffix';
    _record(message, level: level, tag: 'SecureWave.VPN');
  }

  static void _record(
    String message, {
    required int level,
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_retainLogsInMemory) {
      final entry =
          AppLogEntry(message, level: level, timestamp: DateTime.now());
      final logs = List<AppLogEntry>.from(logStream.value)..add(entry);
      if (logs.length > 200) {
        logs.removeRange(0, logs.length - 200);
      }
      logStream.value = logs;
    }

    if (_debugLoggingEnabled || level >= 900) {
      log(message,
          name: tag, level: level, error: error, stackTrace: stackTrace);
    }
  }

  static String _formatFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return '';
    final parts = <String>[];
    for (final entry in fields.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      final value = _shouldRedactField(key) ? '[REDACTED]' : entry.value;
      final text = value == null ? 'null' : value.toString().replaceAll(' ', '_');
      parts.add('$key=$text');
    }
    return parts.join(' ');
  }

  static bool _shouldRedactField(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'email' ||
        normalized.endsWith('_email') ||
        normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized.contains('cookie') ||
        normalized.contains('private_key');
  }
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver({this.onStateChange});

  final ValueChanged<AppLifecycleState>? onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.info('Lifecycle: ${state.name}');
    onStateChange?.call(state);
  }
}
