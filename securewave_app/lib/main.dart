import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Capture all Flutter framework errors
      FlutterError.onError = AppLogger.captureFlutterError;

      // Capture platform dispatcher errors (async errors outside Flutter)
      PlatformDispatcher.instance.onError = AppLogger.capturePlatformError;

      AppLogger.info('SecureWave booting');
      runApp(const ProviderScope(child: SecureWaveApp()));
    },
    (error, stackTrace) {
      AppLogger.error('Uncaught zone error', error: error, stackTrace: stackTrace);
    },
  );
}
