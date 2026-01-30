import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';

void main() {
  // Zone guards async errors; bindings + runApp execute in same zone for determinism
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = AppLogger.captureFlutterError;
      PlatformDispatcher.instance.onError = AppLogger.capturePlatformError;

      await AppConfig.load();
      AppLogger.info('SecureWave booting');
      runApp(const ProviderScope(child: SecureWaveApp()));
    },
    (error, stackTrace) {
      AppLogger.error('Uncaught zone error', error: error, stackTrace: stackTrace);
    },
  );
}
