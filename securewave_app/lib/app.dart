import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/boot_controller.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/models/protocol_availability.dart';
import 'core/models/server_region.dart';
import 'core/models/user_account.dart';
import 'core/models/user_plan.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/services/auth_session.dart';
import 'core/services/vpn_service.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'services/auth_service.dart';
import 'services/external_links.dart';
import 'ui/app_ui_v1.dart';

part 'ui/ui_models.dart';
part 'ui/ui_primitives.dart';
part 'ui/connection_widgets.dart';
part 'ui/auth_screen.dart';
part 'ui/main_shell.dart';
part 'ui/connect_screen.dart';
part 'ui/catalog_screens.dart';

typedef FreshTheme = AppUIv1;

class SecureWaveApp extends ConsumerStatefulWidget {
  const SecureWaveApp({super.key});

  @override
  ConsumerState<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends ConsumerState<SecureWaveApp> {
  late final AppLifecycleObserver _observer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver(onStateChange: _handleLifecycle);
    WidgetsBinding.instance.addObserver(_observer);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = !results.contains(ConnectivityResult.none);
      unawaited(
        ref
            .read(vpnStateProvider.notifier)
            .handleConnectivityChange(hasNetwork: hasNetwork),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final config = await AppConfig.load();
      if (!mounted) return;
      ref.read(appConfigProvider.notifier).state = config;
      ref.read(vpnStateProvider.notifier).resumeRateUpdates();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ref.read(vpnStateProvider.notifier).pauseRateUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: AppUIv1.theme,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootControllerProvider).state;
    final session = ref.watch(authSessionProvider);
    final config = ref.watch(appConfigProvider);

    if (boot.status == BootStatus.initializing || !session.isInitialized) {
      return _BootView(message: boot.errorMessage);
    }

    if (!session.isAuthenticated && !config.skipLoginForDevelopment) {
      return const _AuthScreen();
    }

    return const _MainShell();
  }
}
