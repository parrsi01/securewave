import 'dart:developer';

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
  static final ValueNotifier<List<AppLogEntry>> logStream =
      ValueNotifier<List<AppLogEntry>>(<AppLogEntry>[]);
  static final ValueNotifier<AppErrorEntry?> errorStream = ValueNotifier<AppErrorEntry?>(null);

  static void info(String message, {String tag = 'SecureWave'}) {
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
    _record(message, level: 1000, tag: tag, error: error, stackTrace: stackTrace);
    errorStream.value = AppErrorEntry(message: message, error: error, stackTrace: stackTrace);
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

  static void _record(
    String message, {
    required int level,
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = AppLogEntry(message, level: level, timestamp: DateTime.now());
    final logs = List<AppLogEntry>.from(logStream.value)..add(entry);
    if (logs.length > 200) {
      logs.removeRange(0, logs.length - 200);
    }
    logStream.value = logs;
    log(message, name: tag, level: level, error: error, stackTrace: stackTrace);
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
