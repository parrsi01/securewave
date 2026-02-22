import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../services/auth_session.dart';
import '../services/secure_storage.dart';
import '../state/vpn_state.dart';

enum BootStatus { initializing, ready, failed }

class BootState {
  const BootState({
    required this.status,
    this.errorMessage,
    this.stepLabel,
    this.stepDetail,
  });

  final BootStatus status;
  final String? errorMessage;
  final String? stepLabel;
  final String? stepDetail;

  BootState copyWith({
    BootStatus? status,
    String? errorMessage,
    String? stepLabel,
    String? stepDetail,
  }) {
    return BootState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      stepLabel: stepLabel ?? this.stepLabel,
      stepDetail: stepDetail ?? this.stepDetail,
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
  BootState _state = const BootState(
    status: BootStatus.initializing,
    stepLabel: 'Starting SecureWave',
    stepDetail: 'Preparing startup services.',
  );

  BootState get state => _state;

  Future<void> _initialize() async {
    AppLogger.info('Boot: start');
    try {
      _setStep(
        'Preparing startup',
        detail: 'Loading configuration and restoring your previous session.',
      );
      // Time-bounded initialization: 10 second timeout
      await _initializeWithTimeout();
      _state = _state.copyWith(
        status: BootStatus.ready,
        stepLabel: 'Startup complete',
        stepDetail: 'Opening the app…',
      );
      AppLogger.info('Boot: complete');
    } catch (error, stackTrace) {
      AppLogger.error('Boot failed', error: error, stackTrace: stackTrace);
      // Safe mode: mark as ready but with error message
      // This allows UI to render with limited functionality
      _state = _state.copyWith(
        status: BootStatus.ready,
        errorMessage: 'Started in safe mode: ${error.toString()}',
        stepLabel: 'Startup recovered in safe mode',
        stepDetail: 'Some features may require a retry after the app opens.',
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
    _setStep(
      'Loading configuration',
      detail: 'Reading API endpoints and startup settings.',
    );
    final config = await _withStepTimeout(
      'Loading configuration',
      const Duration(seconds: 3),
      AppConfig.load,
    );
    _ref.read(appConfigProvider.notifier).state = config;
    AppLogger.info('Boot: config loaded');
    final storage = SecureStorage();

    _setStep(
      'Checking saved session',
      detail: 'Reading local auth state and secure storage.',
    );
    if (config.resetSessionOnBoot) {
      _setStep(
        'Resetting saved session',
        detail: 'Clearing old credentials because reset-on-boot is enabled.',
      );
      final resetDone = (await _withStepTimeout(
            'Reading reset-session flag',
            const Duration(seconds: 2),
            () => storage.getBool(SecureStorage.resetSessionDoneKey),
          )) ??
          false;
      if (!resetDone) {
        await _withStepTimeout(
          'Clearing saved session',
          const Duration(seconds: 4),
          () => _ref.read(authSessionProvider).clearSession(),
        );
        await _withStepTimeout(
          'Saving reset-session flag',
          const Duration(seconds: 2),
          () => storage.saveBool(SecureStorage.resetSessionDoneKey, true),
        );
        AppLogger.info('Boot: session reset');
      }
    }

    // Step 2: Restore VPN server selection (can fail gracefully)
    try {
      _setStep(
        'Restoring last server',
        detail: 'Loading your previous VPN location selection.',
      );
      final selectedServer = await _withStepTimeout(
        'Restoring last server',
        const Duration(seconds: 2),
        () => storage.getString(SecureStorage.selectedServerKey),
      );
      if (selectedServer != null) {
        _ref.read(vpnStateProvider.notifier).selectServer(selectedServer);
        AppLogger.info('Boot: restored server $selectedServer');
      }
    } catch (error) {
      AppLogger.warning('Boot: could not restore server selection');
    }

    // Step 3: (reserved for future security posture initialization)
    _setStep(
      'Finalizing startup',
      detail: 'Starting navigation and preparing the app interface.',
    );
  }

  void _setStep(String label, {String? detail}) {
    _state = _state.copyWith(
      stepLabel: label,
      stepDetail: detail,
    );
    notifyListeners();
    AppLogger.info(
      'Boot: step="$label"${detail == null ? "" : " detail=\"$detail\""}',
    );
  }

  Future<T> _withStepTimeout<T>(
    String stepName,
    Duration timeout,
    Future<T> Function() action,
  ) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'Boot step timed out: $stepName (${timeout.inSeconds}s)',
      );
    }
  }
}
