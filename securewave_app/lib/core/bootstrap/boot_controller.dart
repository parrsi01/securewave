import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../services/auth_session.dart';
import '../services/secure_storage.dart';
import '../state/app_state.dart';
import '../state/vpn_state.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

enum BootStatus { initializing, ready, failed }

class BootState {
  const BootState({required this.status, this.errorMessage});

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
    await _doInitialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
          'Boot initialization timed out after 10 seconds',
        );
      },
    );
  }

  Future<void> _doInitialize() async {
    // Step 1: Load config (must succeed)
    final config = await AppConfig.load();
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
        await session.clearSession();
        await storage.saveBool(SecureStorage.resetSessionDoneKey, true);
        AppLogger.info('Boot: session reset');
      }
    }

    if (session.hasStoredSession && !config.debugAutoLogin) {
      try {
        final account = await _ref.read(apiClientProvider).fetchCurrentUser();
        if (!account.isActive) {
          throw StateError('Stored account is inactive.');
        }
        session.acceptRestoredSession();
        await storage.saveAccountOwnerEmail(account.email.trim().toLowerCase());
        AppLogger.info('Boot: stored session verified');
      } catch (_) {
        await session.clearSession();
        await storage.clearVpnRuntimeState();
        await storage.clearAccountOwnerEmail();
        AppLogger.warning('Boot: stored session rejected and cleared');
      }
    }

    if (config.debugAutoLogin) {
      final email = config.debugEmail?.trim() ?? '';
      final password = config.debugPassword ?? '';
      if (email.isEmpty || password.isEmpty) {
        throw StateError(
          'Debug auto-login requires SECUREWAVE_DEBUG_EMAIL and '
          'SECUREWAVE_DEBUG_PASSWORD.',
        );
      }
      final normalizedEmail = email.toLowerCase();
      final storedOwner = (await storage.getAccountOwnerEmail())
          ?.trim()
          .toLowerCase();
      var restoredSameAccount = false;
      if (session.hasStoredSession) {
        try {
          final account = await _ref.read(apiClientProvider).fetchCurrentUser();
          restoredSameAccount =
              account.email.trim().toLowerCase() == normalizedEmail;
          if (restoredSameAccount) {
            session.acceptRestoredSession();
            await storage.saveAccountOwnerEmail(normalizedEmail);
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
          await _ref
              .read(authServiceProvider)
              .login(
                email: email,
                password: password,
                preserveVpnRuntime:
                    storedOwner == null || storedOwner == normalizedEmail,
              );
        } catch (_) {
          // Never leave an expired token looking like a valid signed-in
          // session. The app can then present the real sign-in screen instead
          // of cascading 401 errors in account-backed panels.
          await session.clearSession();
          rethrow;
        }
        AppLogger.info('Boot: debug demo account signed in');
      }

      // A provider may have attempted an authenticated request while the
      // stored token was being verified. Drop any cached failure now that the
      // session is known-good so account data loads with the current token.
      _ref.invalidate(currentUserProvider);
      _ref.invalidate(userPlanProvider);
      _ref.invalidate(serversProvider);
    }

    // Step 2: Restore VPN server selection (can fail gracefully)
    try {
      final selectedServer = await storage.getString(
        SecureStorage.selectedServerKey,
      );
      if (selectedServer != null) {
        _ref.read(vpnStateProvider.notifier).selectServer(selectedServer);
        AppLogger.info('Boot: restored server $selectedServer');
      }
    } catch (error) {
      AppLogger.warning('Boot: could not restore server selection');
    }

    // Step 3: (reserved for future security posture initialization)
  }
}
