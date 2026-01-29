import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logging/app_logger.dart';
import 'features/bootstrap/fallback_error_screen.dart';
import 'router.dart';
import 'ui/app_ui_v1.dart';

class SecureWaveApp extends ConsumerStatefulWidget {
  const SecureWaveApp({super.key});

  @override
  ConsumerState<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends ConsumerState<SecureWaveApp> {
  late final AppLifecycleObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_observer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'SecureWave',
      theme: AppUIv1.theme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return ValueListenableBuilder<AppErrorEntry?>(
          valueListenable: AppLogger.errorStream,
          builder: (context, error, _) {
            if (error == null) return child ?? const SizedBox.shrink();
            return FallbackErrorScreen(
              message: error.message,
              error: error.error,
              stackTrace: error.stackTrace,
            );
          },
        );
      },
    );
  }
}
