import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  AuthState copyWith({bool? isLoading, String? errorMessage}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _ref.read(authServiceProvider).login(email: email, password: password);
    } catch (error, stackTrace) {
      AppLogger.error('Login failed', error: error, stackTrace: stackTrace);
      state = state.copyWith(
        errorMessage: ApiError.messageFrom(
          error,
          fallback: 'We could not sign you in. Check your details and try again.',
        ),
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> register({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _ref.read(authServiceProvider).register(email: email, password: password);
    } catch (error) {
      AppLogger.error('Registration failed', error: error);
      state = state.copyWith(
        errorMessage: ApiError.messageFrom(
          error,
          fallback: 'We could not create your account. Please try again.',
        ),
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
