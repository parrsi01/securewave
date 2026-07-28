import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool get hasStoredSession => _accessToken != null && _accessToken!.isNotEmpty;
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
        // A stored token is only a restoration candidate until /auth/me
        // accepts it during application boot.
        _isAuthenticated = false;
      }
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setSession({
    required String accessToken,
    String? refreshToken,
  }) async {
    await ensureInitialized();
    _accessToken = accessToken;
    _isAuthenticated = true;
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    notifyListeners();
  }

  void acceptRestoredSession() {
    if (!hasStoredSession) {
      throw StateError('No stored session is available to accept.');
    }
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
