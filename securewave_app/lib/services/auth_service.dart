import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/services/auth_session.dart';
import '../core/services/secure_storage.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.watch(apiClientProvider);
  final session = ref.watch(authSessionProvider);
  return AuthService(api, session);
});

class AuthService {
  AuthService(this._api, this._session);

  final ApiClient _api;
  final AuthSession _session;

  Future<void> login({required String email, required String password}) async {
    final tokens = await _api.login(email: email, password: password);
    await SecureStorage().clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  Future<void> register(
      {required String email, required String password}) async {
    var tokens = await _api.register(email: email, password: password);
    if (tokens == null) {
      AppLogger.warning(
          'Registration completed without token payload; attempting sign-in.');
      try {
        tokens = await _api.login(email: email, password: password);
      } catch (_) {
        throw StateError(
          'Registration completed, but automatic sign-in failed. Verify the account, then sign in.',
        );
      }
    }
    await SecureStorage().clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      // Local credentials must be removed even when the control plane is
      // unreachable, so logout never strands a usable session on disk.
      await _session.clearSession();
      await SecureStorage().clearVpnRuntimeState();
    }
  }
}
