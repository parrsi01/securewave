import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';

Future<void> testBackend() async {
  try {
    final config = await AppConfig.load();
    if (kDebugMode) {
      debugPrint(
        '[SW_API] {"event":"runtime_base_url","source":"${config.configSource.name}",'
        '"base_url":"${config.apiBaseUrl}"}',
      );
    }
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final response = await dio.get<Map<String, dynamic>>('/health');
    if (kDebugMode) {
      debugPrint(
        '[SW_API] {"event":"runtime_health","status":${response.statusCode ?? 200},'
        '"data_keys":${response.data?.keys.toList() ?? const <String>[]}}',
      );
    }
    AppLogger.info(
      'Runtime health check status=${response.statusCode ?? 200} '
      'baseUrl=${config.apiBaseUrl}',
    );
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('[SW_API] {"event":"runtime_health_fail","error":"$error"}');
    }
    AppLogger.error(
      'Runtime health check failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
