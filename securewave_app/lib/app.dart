import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/services/network_path.dart';
import 'core/state/vpn_state.dart';
import 'navigation/app_router.dart';
import 'ui/theme/securewave_theme.dart';

class SecureWaveApp extends ConsumerStatefulWidget {
  const SecureWaveApp({super.key});

  @override
  ConsumerState<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends ConsumerState<SecureWaveApp> {
  late final AppLifecycleObserver _observer;
  late final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  NetworkPathKind _lastNetworkPath = NetworkPathKind.offline;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity();
    _observer = AppLifecycleObserver(onStateChange: _handleLifecycle);
    WidgetsBinding.instance.addObserver(_observer);
    unawaited(_primeConnectivityState());
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityEvent,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _primeConnectivityState() async {
    final results = await _connectivity.checkConnectivity();
    if (!mounted) return;
    _handleConnectivityEvent(results);
  }

  bool _sameConfig(AppConfig a, AppConfig b) {
    return a.apiBaseUrl == b.apiBaseUrl &&
        a.portalUrl == b.portalUrl &&
        a.upgradeUrl == b.upgradeUrl &&
        a.resetSessionOnBoot == b.resetSessionOnBoot &&
        a.configSource == b.configSource &&
        a.httpsPreferred == b.httpsPreferred;
  }

  void _handleConnectivityEvent(List<ConnectivityResult> results) {
    final nextPath = networkPathKindFromResults(results);
    final previousPath = _lastNetworkPath;
    final pathChanged = previousPath != nextPath;
    final onlineChanged = previousPath.isOnline != nextPath.isOnline;
    if (!pathChanged && !onlineChanged) {
      return;
    }
    _lastNetworkPath = nextPath;

    AppLogger.vpn(
      'NETWORK',
      'PATH_CHANGED',
      fields: <String, Object?>{
        'previous': previousPath.label,
        'current': nextPath.label,
        'online': nextPath.isOnline,
      },
    );

    final notifier = ref.read(vpnStateProvider.notifier);
    if (onlineChanged) {
      unawaited(
        notifier.handleConnectivityChange(hasNetwork: nextPath.isOnline),
      );
    }
    if (pathChanged) {
      unawaited(
        notifier.handleNetworkPathChange(
          previous: previousPath,
          current: nextPath,
        ),
      );
    }
  }

  Future<void> _handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final currentConfig = ref.read(appConfigProvider);
      final config = await AppConfig.load();
      if (!mounted) return;
      if (!_sameConfig(currentConfig, config)) {
        ref.read(appConfigProvider.notifier).state = config;
      }
      ref.read(vpnStateProvider.notifier).resumeRateUpdates();
      return;
    }

    if (state == AppLifecycleState.detached) {
      await ref.read(vpnStateProvider.notifier).safeShutdown();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(vpnStateProvider.notifier).pauseRateUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'SecureWave',
      theme: SecureWaveTheme.light(),
      darkTheme: SecureWaveTheme.dark(),
      themeMode: SecureWaveTheme.defaultThemeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
