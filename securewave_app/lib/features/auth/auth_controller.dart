import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/utils/api_error.dart';
import '../../core/logging/app_logger.dart';
import '../../services/auth_service.dart';

class AuthState {
  const AuthState({
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  static const Object _unset = Object();

  AuthState copyWith({bool? isLoading, Object? errorMessage = _unset}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _ref
          .read(authServiceProvider)
          .login(email: email, password: password);
      // Clear stale pre-auth caches so providers re-fetch with valid token.
      _ref.invalidate(serversProvider);
      _ref.invalidate(userPlanProvider);
      _ref.invalidate(vpnProtocolCatalogProvider);
      AppLogger.debug(
        '[AUTH_VERIFY] login ok — serversProvider+userPlanProvider+vpnProtocolCatalogProvider invalidated',
        tag: 'SecureWave.Auth',
      );
    } catch (error, stackTrace) {
      AppLogger.debug('[AUTH_VERIFY] login failed', tag: 'SecureWave.Auth');
      AppLogger.error('Login failed', error: error, stackTrace: stackTrace);
      state = state.copyWith(
        errorMessage: ApiError.messageFrom(
          error,
          fallback:
              'We could not sign you in. Check your details and try again.',
        ),
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<RegistrationOutcome?> register(
      {required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final outcome = await _ref
          .read(authServiceProvider)
          .register(email: email, password: password);
      _ref.invalidate(serversProvider);
      _ref.invalidate(userPlanProvider);
      _ref.invalidate(vpnProtocolCatalogProvider);
      AppLogger.debug(
        '[AUTH_VERIFY] register ok — serversProvider+userPlanProvider+vpnProtocolCatalogProvider invalidated',
        tag: 'SecureWave.Auth',
      );
      return outcome;
    } catch (error, stackTrace) {
      AppLogger.debug(
        '[AUTH_VERIFY] register failed',
        tag: 'SecureWave.Auth',
      );
      AppLogger.error('Registration failed', error: error, stackTrace: stackTrace);
      state = state.copyWith(
        errorMessage: ApiError.messageFrom(
          error,
          fallback: 'We could not create your account. Please try again.',
        ),
      );
      return null;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
