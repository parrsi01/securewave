import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = AppLogger.captureFlutterError;
  PlatformDispatcher.instance.onError = AppLogger.capturePlatformError;

  runZonedGuarded(
    () {
      AppLogger.info('SecureWave booting');
      runApp(const ProviderScope(child: SecureWaveApp()));
    },
    (error, stackTrace) => AppLogger.error('Zone error', error: error, stackTrace: stackTrace),
  );
}
