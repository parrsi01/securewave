import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> login({
    required String email,
    required String password,
    bool preserveVpnRuntime = false,
  }) async {
    final tokens = await _api.login(email: email, password: password);
    final storage = SecureStorage();
    final normalizedEmail = email.trim().toLowerCase();
    final previousOwner = (await storage.getAccountOwnerEmail())
        ?.trim()
        .toLowerCase();
    final sameKnownAccount = previousOwner == normalizedEmail;
    if (!sameKnownAccount && !preserveVpnRuntime) {
      await storage.clearVpnRuntimeState();
    }
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await storage.saveAccountOwnerEmail(normalizedEmail);
  }

  Future<bool> register({
    required String email,
    required String password,
  }) async {
    final tokens = await _api.register(email: email, password: password);
    if (tokens == null) {
      return false;
    }
    final storage = SecureStorage();
    await storage.clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await storage.saveAccountOwnerEmail(email.trim().toLowerCase());
    return true;
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      // Local credentials must be removed even when the control plane is
      // unreachable, so logout never strands a usable session on disk.
      await _session.clearSession();
      final storage = SecureStorage();
      await storage.clearVpnRuntimeState();
      await storage.clearAccountOwnerEmail();
    }
  }
}
