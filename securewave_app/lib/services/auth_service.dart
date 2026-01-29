import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/services/auth_session.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.read(apiClientProvider);
  final session = ref.read(authSessionProvider);
  return AuthService(api, session);
});

class AuthService {
  AuthService(this._api, this._session);

  final ApiClient _api;
  final AuthSession _session;

  Future<void> login({required String email, required String password}) async {
    final tokens = await _api.login(email: email, password: password);
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  Future<void> register({required String email, required String password}) async {
    final tokens = await _api.register(email: email, password: password);
    if (tokens == null) {
      AppLogger.warning('Registration completed without token payload.');
      return;
    }
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }
}
