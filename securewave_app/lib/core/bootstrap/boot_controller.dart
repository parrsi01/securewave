import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../models/user_account.dart';
import '../services/auth_session.dart';
import '../services/secure_storage.dart';
import '../state/app_state.dart';
import '../state/vpn_state.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

enum BootStatus { initializing, ready, offline, authRejected, failed }

class BootState {
  const BootState({
    required this.status,
    this.errorMessage,
  });

  final BootStatus status;
  final String? errorMessage;

  BootState copyWith({
    BootStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return BootState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final bootControllerProvider = ChangeNotifierProvider<BootController>((ref) {
  return BootController(ref);
});

class BootController extends ChangeNotifier {
  BootController(
    this._ref, {
    Future<AppConfig> Function()? configLoader,
    BootState? initialState,
  })  : _configLoader = configLoader ?? AppConfig.load,
        _state =
            initialState ?? const BootState(status: BootStatus.initializing) {
    if (initialState == null) _startInitialization();
  }

  final Ref _ref;
  final Future<AppConfig> Function() _configLoader;
  BootState _state;
  Future<void>? _activeInitialization;
  Future<UserAccount>? _currentUserRequest;
  bool _disposed = false;

  BootState get state => _state;

  Future<void> ensureInitialized() {
    final active = _activeInitialization;
    if (active != null) return active;
    if (_state.status == BootStatus.ready ||
        _state.status == BootStatus.authRejected ||
        _state.status == BootStatus.offline) {
      return Future<void>.value();
    }
    return _startInitialization();
  }

  Future<void> retry() {
    if (_state.status != BootStatus.offline &&
        _state.status != BootStatus.failed) {
      return ensureInitialized();
    }
    return _startInitialization();
  }

  void markSessionAuthenticated() {
    if (_state.status == BootStatus.authRejected ||
        _state.status == BootStatus.offline ||
        _state.status == BootStatus.failed) {
      _setState(const BootState(status: BootStatus.ready));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _startInitialization() {
    final active = _activeInitialization;
    if (active != null) return active;
    final next = _initialize();
    _activeInitialization = next;
    next.then<void>(
      (_) => _clearActiveInitialization(next),
      onError: (Object _, StackTrace __) => _clearActiveInitialization(next),
    );
    return next;
  }

  void _clearActiveInitialization(Future<void> completed) {
    if (identical(_activeInitialization, completed)) {
      _activeInitialization = null;
    }
  }

  void _setState(BootState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<void> _initialize() async {
    AppLogger.info('Boot: start');
    _setState(const BootState(status: BootStatus.initializing));
    try {
      final result = await _initializeWithTimeout();
      _setState(BootState(status: result.status, errorMessage: result.message));
      AppLogger.info('Boot: ${result.status.name}');
    } catch (error, stackTrace) {
      AppLogger.error('Boot failed', error: error, stackTrace: stackTrace);
      _setState(const BootState(
        status: BootStatus.failed,
        errorMessage: 'SecureWave could not finish startup. Retry to continue.',
      ));
      AppLogger.warning('Boot: startup requires a retry');
    }
  }

  Future<_BootResult> _initializeWithTimeout() async {
    return _doInitialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
            'Boot initialization timed out after 10 seconds');
      },
    );
  }

  Future<_BootResult> _doInitialize() async {
    // Step 1: Load config (must succeed)
    final config = await _configLoader();
    _ref.read(appConfigProvider.notifier).state = config;
    AppLogger.info('Boot: config loaded');
    final storage = SecureStorage();
    final session = _ref.read(authSessionProvider);
    await session.ensureInitialized();
    AppLogger.info('Boot: session restored');

    if (config.resetSessionOnBoot) {
      final resetDone =
          await storage.getBool(SecureStorage.resetSessionDoneKey) ?? false;
      if (!resetDone) {
        await _disconnectVpnForSessionState();
        await _ref.read(authServiceProvider).clearLocalSessionState();
        await storage.saveBool(SecureStorage.resetSessionDoneKey, true);
        AppLogger.info('Boot: session reset');
      }
    }

    if (config.debugAutoLogin) {
      await _runDebugAutoLogin(config, storage, session);
    } else if (session.isAuthenticated) {
      final validation = await _validateStoredSession(session, storage);
      switch (validation) {
        case _SessionValidation.valid:
        case _SessionValidation.superseded:
          break;
        case _SessionValidation.offline:
          return const _BootResult(
            status: BootStatus.offline,
            message:
                'SecureWave cannot reach the control plane. Check your connection and retry.',
          );
        case _SessionValidation.rejected:
          await _disconnectVpnForSessionState();
          await _ref.read(authServiceProvider).clearLocalSessionState();
          return const _BootResult(
            status: BootStatus.authRejected,
            message:
                'Your saved session expired. Create an account or sign in again.',
          );
      }
    }

    // Step 2: Restore VPN server selection (can fail gracefully)
    try {
      final selectedServer =
          await storage.getString(SecureStorage.selectedServerKey);
      if (selectedServer != null) {
        _ref.read(vpnStateProvider.notifier).selectServer(selectedServer);
        AppLogger.info('Boot: restored server $selectedServer');
      }
    } catch (error) {
      AppLogger.warning('Boot: could not restore server selection');
    }

    return const _BootResult(status: BootStatus.ready);
  }

  Future<void> _runDebugAutoLogin(
    AppConfig config,
    SecureStorage storage,
    AuthSession session,
  ) async {
    final email = config.debugEmail?.trim() ?? '';
    final password = config.debugPassword ?? '';
    if (email.isEmpty || password.isEmpty) {
      throw StateError(
        'Debug auto-login requires SECUREWAVE_DEBUG_EMAIL and '
        'SECUREWAVE_DEBUG_PASSWORD.',
      );
    }
    final normalizedEmail = email.toLowerCase();
    final storedOwner =
        (await storage.getAccountOwnerEmail())?.trim().toLowerCase();
    var restoredSameAccount = false;
    if (session.isAuthenticated) {
      try {
        final account = await _ref.read(apiClientProvider).fetchCurrentUser();
        restoredSameAccount =
            account.email.trim().toLowerCase() == normalizedEmail;
        if (restoredSameAccount) {
          await storage.saveAccountOwnerEmail(normalizedEmail);
          session.markSessionValidated();
          AppLogger.info('Boot: verified existing debug account session');
        }
      } catch (_) {
        AppLogger.warning(
          'Boot: stored debug session was not accepted; refreshing login.',
        );
      }
    }
    if (!restoredSameAccount) {
      try {
        await _ref.read(authServiceProvider).login(
              email: email,
              password: password,
              preserveVpnRuntime:
                  storedOwner == null || storedOwner == normalizedEmail,
            );
      } catch (_) {
        await session.clearSession();
        rethrow;
      }
      AppLogger.info('Boot: debug demo account signed in');
    }

    _ref.invalidate(currentUserProvider);
    _ref.invalidate(userPlanProvider);
    _ref.invalidate(serversProvider);
  }

  Future<_SessionValidation> _validateStoredSession(
    AuthSession session,
    SecureStorage storage,
  ) async {
    final token = session.accessToken;
    if (!session.isAuthenticated || token == null || token.isEmpty) {
      return _SessionValidation.valid;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final account = await _fetchCurrentUserOnce().timeout(
          const Duration(seconds: 3),
        );
        if (!session.isAuthenticated || session.accessToken != token) {
          return _SessionValidation.superseded;
        }
        final email = account.email.trim().toLowerCase();
        if (email.isNotEmpty) {
          await storage.saveAccountOwnerEmail(email);
        }
        session.markSessionValidated();
        return _SessionValidation.valid;
      } catch (error) {
        if (!session.isAuthenticated || session.accessToken != token) {
          return _SessionValidation.superseded;
        }
        if (_isAuthRejection(error)) return _SessionValidation.rejected;
        if (attempt == 1) return _SessionValidation.offline;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return _SessionValidation.offline;
  }

  Future<UserAccount> _fetchCurrentUserOnce() {
    final active = _currentUserRequest;
    if (active != null) return active;
    final next = _ref.read(apiClientProvider).fetchCurrentUser();
    _currentUserRequest = next;
    next.then<void>(
      (_) {
        if (identical(_currentUserRequest, next)) _currentUserRequest = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_currentUserRequest, next)) _currentUserRequest = null;
      },
    );
    return next;
  }

  bool _isAuthRejection(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) return true;
    final data = error.response?.data;
    if (data is! Map) return false;
    final rawError = data['error'];
    final code = data['code'] ??
        (rawError is Map ? rawError['code'] : null) ??
        data['detail'];
    return code?.toString().toLowerCase() == 'unauthorized';
  }

  Future<void> _disconnectVpnForSessionState() async {
    try {
      await _ref
          .read(vpnStateProvider.notifier)
          .disconnectForSessionInvalidation();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Boot: VPN session cleanup failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

class _BootResult {
  const _BootResult({required this.status, this.message});

  final BootStatus status;
  final String? message;
}

enum _SessionValidation { valid, offline, rejected, superseded }
