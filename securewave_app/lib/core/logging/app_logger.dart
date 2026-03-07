import 'dart:developer';

import 'package:flutter/widgets.dart';

enum AppLogCategory {
  ui('UI'),
  api('API'),
  vpnState('VPN_STATE'),
  auth('AUTH'),
  server('SERVER'),
  routing('ROUTING'),
  tunnel('TUNNEL'),
  diagnostics('DIAGNOSTICS'),
  lifecycle('LIFECYCLE'),
  app('APP');

  const AppLogCategory(this.label);

  final String label;
}

class AppLogEntry {
  AppLogEntry(
    this.message, {
    required this.level,
    required this.timestamp,
    required this.category,
    this.fields = const <String, Object?>{},
  });

  final String message;
  final int level;
  final DateTime timestamp;
  final AppLogCategory category;
  final Map<String, Object?> fields;

  @override
  String toString() {
    final serializedFields = fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return '[${timestamp.toIso8601String()}] [${category.label}] $message'
        '${serializedFields.isEmpty ? '' : ' $serializedFields'}';
  }
}

class AppErrorEntry {
  AppErrorEntry({required this.message, this.error, this.stackTrace});

  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

class AppLogger {
  static const int _maxLogEntries = 500;

  static final ValueNotifier<List<AppLogEntry>> logStream =
      ValueNotifier<List<AppLogEntry>>(<AppLogEntry>[]);
  static final ValueNotifier<AppErrorEntry?> errorStream =
      ValueNotifier<AppErrorEntry?>(null);

  static void info(
    String message, {
    String tag = 'SecureWave',
    AppLogCategory category = AppLogCategory.app,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(message, level: 500, tag: tag, category: category, fields: fields);
  }

  static void warning(
    String message, {
    String tag = 'SecureWave',
    AppLogCategory category = AppLogCategory.app,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(message, level: 900, tag: tag, category: category, fields: fields);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'SecureWave',
    AppLogCategory category = AppLogCategory.app,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(
      message,
      level: 1000,
      tag: tag,
      category: category,
      fields: fields,
      error: error,
      stackTrace: stackTrace,
    );
    errorStream.value =
        AppErrorEntry(message: message, error: error, stackTrace: stackTrace);
  }

  static void vpnStateTransition({
    required String previous,
    required String next,
    required String? server,
    required String protocol,
    int? latencyMs,
  }) {
    info(
      'transition',
      category: AppLogCategory.vpnState,
      fields: <String, Object?>{
        'previous': previous,
        'next': next,
        'server': server,
        'protocol': protocol,
        'latency': latencyMs == null ? null : '${latencyMs}ms',
      },
    );
  }

  static void uiAction(
    String action, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    info(action, category: AppLogCategory.ui, fields: fields);
  }

  static void apiRequest(
    String method,
    String endpoint, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    info(
      'request',
      category: AppLogCategory.api,
      fields: <String, Object?>{
        'method': method,
        'endpoint': endpoint,
        ...fields,
      },
    );
  }

  static void apiResponse(
    String method,
    String endpoint, {
    int? statusCode,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    info(
      'response',
      category: AppLogCategory.api,
      fields: <String, Object?>{
        'method': method,
        'endpoint': endpoint,
        'status_code': statusCode,
        ...fields,
      },
    );
  }

  static void auth(String message,
      {Map<String, Object?> fields = const <String, Object?>{}}) {
    info(message, category: AppLogCategory.auth, fields: fields);
  }

  static void server(String message,
      {Map<String, Object?> fields = const <String, Object?>{}}) {
    info(message, category: AppLogCategory.server, fields: fields);
  }

  static void routing(String message,
      {Map<String, Object?> fields = const <String, Object?>{}}) {
    info(message, category: AppLogCategory.routing, fields: fields);
  }

  static void tunnel(String message,
      {Map<String, Object?> fields = const <String, Object?>{}}) {
    info(message, category: AppLogCategory.tunnel, fields: fields);
  }

  static void diagnostics(
    String message, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    info(message, category: AppLogCategory.diagnostics, fields: fields);
  }

  static void captureFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    error(
      'Flutter error: ${details.exceptionAsString()}',
      error: details.exception,
      stackTrace: details.stack,
      category: AppLogCategory.app,
    );
  }

  static bool capturePlatformError(Object error, StackTrace stackTrace) {
    AppLogger.error(
      'Platform error',
      error: error,
      stackTrace: stackTrace,
      category: AppLogCategory.app,
    );
    return true;
  }

  static void _record(
    String message, {
    required int level,
    required String tag,
    required AppLogCategory category,
    required Map<String, Object?> fields,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = AppLogEntry(
      message,
      level: level,
      timestamp: DateTime.now(),
      category: category,
      fields: fields,
    );
    final logs = List<AppLogEntry>.from(logStream.value)..add(entry);
    if (logs.length > _maxLogEntries) {
      logs.removeRange(0, logs.length - _maxLogEntries);
    }
    logStream.value = logs;
    log(entry.toString(),
        name: tag, level: level, error: error, stackTrace: stackTrace);
  }
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver({this.onStateChange});

  final ValueChanged<AppLifecycleState>? onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLogger.info(
      'lifecycle_change',
      category: AppLogCategory.lifecycle,
      fields: <String, Object?>{'state': state.name},
    );
    onStateChange?.call(state);
  }
}
