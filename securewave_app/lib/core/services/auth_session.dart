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

  bool _isAuthenticated = false;
  bool _isInitialized = false;
  String? _accessToken;
  String? _refreshToken;

  bool get isAuthenticated => _isAuthenticated;
  bool get isInitialized => _isInitialized;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  Future<void> _initializeSession() async {
    final token = await _storage.getAccessToken();
    final refreshToken = await _storage.getRefreshToken();
    if (token != null && token.isNotEmpty) {
      _accessToken = token;
      _refreshToken = refreshToken;
      _isAuthenticated = true;
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setSession(
      {required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _isAuthenticated = true;
    await _storage.saveTokens(
        accessToken: accessToken, refreshToken: refreshToken);
    notifyListeners();
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _isAuthenticated = false;
    await _storage.clearTokens();
    notifyListeners();
  }
}
