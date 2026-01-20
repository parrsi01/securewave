import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage.dart';

final authSessionProvider = ChangeNotifierProvider<AuthSession>((ref) {
  return AuthSession(ref.read);
});

class AuthSession extends ChangeNotifier {
  AuthSession(this._read) {
    _bootstrap();
  }

  final Reader _read;
  final _storage = SecureStorage();

  bool _isAuthenticated = false;
  String? _accessToken;

  bool get isAuthenticated => _isAuthenticated;
  String? get accessToken => _accessToken;

  Future<void> _bootstrap() async {
    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      _accessToken = token;
      _isAuthenticated = true;
    }
    notifyListeners();
  }

  Future<void> setSession({required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    _isAuthenticated = true;
    await _storage.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    notifyListeners();
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _isAuthenticated = false;
    await _storage.clearTokens();
    notifyListeners();
  }
}
