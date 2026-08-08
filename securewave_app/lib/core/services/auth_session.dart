import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'secure_storage.dart';

final authSessionProvider = ChangeNotifierProvider<AuthSession>((ref) {
  return AuthSession();
});

class AuthSession extends ChangeNotifier {
  AuthSession() {
    _initializeSession();
  }

  final _storage = SecureStorage();

  bool _isInitialized = false;
  bool _isAuthenticated = false;
  String? _accessToken;
  Future<void>? _initializeFuture;

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _isAuthenticated;
  String? get accessToken => _accessToken;

  Future<void> _initializeSession() async {
    _initializeFuture ??= _restoreSession();
    await _initializeFuture;
  }

  Future<void> ensureInitialized() => _initializeSession();

  Future<void> _restoreSession() async {
    try {
      final token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        _accessToken = token;
        _isAuthenticated = true;
      }
    } catch (_, stackTrace) {
      // A locked Linux keyring must not prevent the signed-out login screen
      // from rendering. Do not fall back to plaintext storage; a later login
      // will retry the platform write and surface a safe error if it remains
      // unavailable.
      AppLogger.warning(
        'Session restore unavailable; continuing signed out.',
      );
      AppLogger.error('Session restore failed', stackTrace: stackTrace);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setSession(
      {required String accessToken, String? refreshToken}) async {
    await ensureInitialized();
    try {
      // Persist first so a keyring failure cannot leave the UI authenticated
      // with a token that the restart/session contract cannot restore.
      await _storage.saveTokens(
          accessToken: accessToken, refreshToken: refreshToken);
    } catch (_, stackTrace) {
      AppLogger.error('Session token storage failed', stackTrace: stackTrace);
      throw SecureStorageUnavailableException();
    }
    _accessToken = accessToken;
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> clearSession() async {
    await ensureInitialized();
    _accessToken = null;
    _isAuthenticated = false;
    await _storage.clearTokens();
    notifyListeners();
  }
}
