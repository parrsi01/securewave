import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';

Future<void> runSecureWaveApp({AppConfig? config}) async {
  // Zone guards async errors; bindings + runApp execute in same zone for determinism
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = AppLogger.captureFlutterError;
      PlatformDispatcher.instance.onError = AppLogger.capturePlatformError;

      if (config == null) await AppConfig.load();
      AppLogger.info('SecureWave booting');
      runApp(
        ProviderScope(
          overrides: config == null
              ? const []
              : [appConfigProvider.overrideWith((_) => config)],
          child: const SecureWaveApp(),
        ),
      );
    },
    (error, stackTrace) {
      AppLogger.error('Uncaught zone error',
          error: error, stackTrace: stackTrace);
    },
  );
}

void main() => runSecureWaveApp();
