import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/services/auth_session.dart';
import '../core/services/secure_storage.dart';
import '../core/state/vpn_state.dart';
import 'api_client.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.watch(apiClientProvider);
  final session = ref.watch(authSessionProvider);
  return AuthService(
    api,
    session,
    disconnectVpn: () =>
        ref.read(vpnStateProvider.notifier).disconnectForSessionInvalidation(),
  );
});

class AuthService {
  AuthService(
    this._api,
    this._session, {
    Future<void> Function()? disconnectVpn,
  }) : _disconnectVpn = disconnectVpn;

  final ApiClient _api;
  final AuthSession _session;
  final Future<void> Function()? _disconnectVpn;

  Future<void> login({
    required String email,
    required String password,
    bool preserveVpnRuntime = false,
  }) async {
    final tokens = await _api.login(email: email, password: password);
    final storage = SecureStorage();
    final normalizedEmail = email.trim().toLowerCase();
    final previousOwner =
        (await storage.getAccountOwnerEmail())?.trim().toLowerCase();
    final sameKnownAccount = previousOwner == normalizedEmail;
    if (!sameKnownAccount && !preserveVpnRuntime) {
      await _disconnectVpn?.call();
      await storage.clearVpnRuntimeState();
    }
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await storage.saveAccountOwnerEmail(normalizedEmail);
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
    final storage = SecureStorage();
    await _disconnectVpn?.call();
    await storage.clearVpnRuntimeState();
    await _session.setSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    await storage.saveAccountOwnerEmail(email.trim().toLowerCase());
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } finally {
      // Local credentials must be removed even when the control plane is
      // unreachable, so logout never strands a usable session on disk.
      try {
        await _disconnectVpn?.call();
      } catch (error, stackTrace) {
        AppLogger.error(
          'Local VPN shutdown during logout failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      await clearLocalSessionState();
    }
  }

  Future<void> clearLocalSessionState() async {
    await _session.clearSession();
    final storage = SecureStorage();
    await storage.clearVpnRuntimeState();
    await storage.clearAccountOwnerEmail();
  }
}
