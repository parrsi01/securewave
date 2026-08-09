import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage.dart';

final authSessionProvider = ChangeNotifierProvider<AuthSession>((ref) {
  return AuthSession();
});

class AuthSession extends ChangeNotifier {
  AuthSession({SecureStorage? storage}) : _storage = storage ?? SecureStorage() {
    _initializeSession();
  }

  final SecureStorage _storage;

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
    } catch (_) {
      _accessToken = null;
      _isAuthenticated = false;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setSession({required String accessToken}) async {
    await ensureInitialized();
    _accessToken = accessToken;
    _isAuthenticated = true;
    await _storage.saveToken(accessToken);
    notifyListeners();
  }

  Future<void> clearSession() async {
    await ensureInitialized();
    _accessToken = null;
    _isAuthenticated = false;
    await _storage.clearToken();
    notifyListeners();
  }
}
