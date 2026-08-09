import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/auth_session.dart';
import '../core/services/secure_storage.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.watch(apiClientProvider);
  final session = ref.watch(authSessionProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthService(api, session, storage);
});

class AuthService {
  AuthService(this._api, this._session, this._storage);

  final ApiClient _api;
  final AuthSession _session;
  final SecureStorage _storage;

  Future<void> login({required String email, required String password}) async {
    final tokens = await _api.login(email: email, password: password);
    await _storage.clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
    );
  }

  Future<void> register(
      {required String email, required String password}) async {
    final tokens = await _api.register(email: email, password: password);
    await _storage.clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
    );
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      // Local credentials must be removed even when the control plane is
      // unreachable, so logout never strands a usable session on disk.
      await _session.clearSession();
      await _storage.clearVpnRuntimeState();
    }
  }
}
