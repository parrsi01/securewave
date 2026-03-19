import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/services/auth_session.dart';
import '../core/services/secure_storage.dart';
import 'api_client.dart';

enum RegistrationOutcome {
  authenticated,
  loginRequired,
}

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.read(apiClientProvider);
  final session = ref.read(authSessionProvider);
  return AuthService(api, session);
});

class AuthService {
  AuthService(
    this._api,
    this._session, {
    SecureStorage? storage,
  }) : _storage = storage ?? SecureStorage();

  final ApiClient _api;
  final AuthSession _session;
  final SecureStorage _storage;

  Future<void> login({required String email, required String password}) async {
    final tokens = await _api.login(email: email, password: password);
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      email: email,
    );
    await _storage.saveRecentLoginEmail(email);
  }

  Future<RegistrationOutcome> register(
      {required String email, required String password}) async {
    final tokens = await _api.register(email: email, password: password);
    if (tokens == null) {
      AppLogger.warning('Registration completed without token payload.');
      await _storage.saveRecentLoginEmail(email);
      return RegistrationOutcome.loginRequired;
    }
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      email: email,
    );
    await _storage.saveRecentLoginEmail(email);
    return RegistrationOutcome.authenticated;
  }
}
