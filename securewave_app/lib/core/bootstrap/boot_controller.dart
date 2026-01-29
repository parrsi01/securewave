import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../services/auth_session.dart';
import '../services/secure_storage.dart';
import '../state/adblock_state.dart';
import '../state/vpn_state.dart';

enum BootStatus { initializing, ready, failed }

class BootState {
  const BootState({
    required this.status,
    this.errorMessage,
  });

  final BootStatus status;
  final String? errorMessage;

  BootState copyWith({BootStatus? status, String? errorMessage}) {
    return BootState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final bootControllerProvider = ChangeNotifierProvider<BootController>((ref) {
  return BootController(ref);
});

class BootController extends ChangeNotifier {
  BootController(this._ref) {
    _initialize();
  }

  final Ref _ref;
  BootState _state = const BootState(status: BootStatus.initializing);

  BootState get state => _state;

  Future<void> _initialize() async {
    AppLogger.info('Boot: start');
    try {
      // Time-bounded initialization: 10 second timeout
      await _initializeWithTimeout();
      _state = _state.copyWith(status: BootStatus.ready);
      AppLogger.info('Boot: complete');
    } catch (error, stackTrace) {
      AppLogger.error('Boot failed', error: error, stackTrace: stackTrace);
      // Safe mode: mark as ready but with error message
      // This allows UI to render with limited functionality
      _state = _state.copyWith(
        status: BootStatus.ready,
        errorMessage: 'Started in safe mode: ${error.toString()}',
      );
      AppLogger.warning('Boot: entering safe mode');
    }
    notifyListeners();
  }

  Future<void> _initializeWithTimeout() async {
    await Future.any([
      _doInitialize(),
      Future.delayed(const Duration(seconds: 10), () {
        throw TimeoutException('Boot initialization timed out after 10 seconds');
      }),
    ]);
  }

  Future<void> _doInitialize() async {
    // Step 1: Load config (must succeed)
    final config = await AppConfig.load();
    _ref.read(appConfigProvider.notifier).state = config;
    AppLogger.info('Boot: config loaded');
    final storage = SecureStorage();

    if (config.resetSessionOnBoot) {
      final resetDone = await storage.getBool(SecureStorage.resetSessionDoneKey) ?? false;
      if (!resetDone) {
        await _ref.read(authSessionProvider).clearSession();
        await storage.saveBool(SecureStorage.resetSessionDoneKey, true);
        AppLogger.info('Boot: session reset');
      }
    }

    // Step 2: Restore VPN server selection (can fail gracefully)
    try {
      final selectedServer = await storage.getString(SecureStorage.selectedServerKey);
      if (selectedServer != null) {
        _ref.read(vpnStateProvider.notifier).selectServer(selectedServer);
        AppLogger.info('Boot: restored server $selectedServer');
      }
    } catch (error) {
      AppLogger.warning('Boot: could not restore server selection');
    }

    // Step 3: Load adblock lists (can fail gracefully)
    try {
      await _ref.read(adblockStateProvider.notifier).load();
      AppLogger.info('Boot: adblock loaded');
    } catch (error) {
      AppLogger.warning('Boot: adblock load failed, will use fallback');
    }
  }
}
