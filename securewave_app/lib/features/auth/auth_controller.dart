import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_service.dart';
import '../../core/services/auth_session.dart';

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
      final api = _ref.read(apiServiceProvider);
      final response = await api.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = response.data as Map<String, dynamic>;
      await _ref.read(authSessionProvider).setSession(
            accessToken: data['access_token'] as String,
            refreshToken: data['refresh_token'] as String?,
          );
    } catch (error) {
      state = state.copyWith(errorMessage: 'Login failed. Check your details and try again.');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> register({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.post('/auth/register', data: {
        'email': email,
        'password': password,
        'password_confirm': password,
      });
      final data = response.data as Map<String, dynamic>;
      if (data['access_token'] != null) {
        await _ref.read(authSessionProvider).setSession(
              accessToken: data['access_token'] as String,
              refreshToken: data['refresh_token'] as String?,
            );
      }
    } catch (error) {
      state = state.copyWith(errorMessage: 'Registration failed. Please try again.');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
