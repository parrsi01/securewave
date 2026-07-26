import 'dart:async';

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
  bool _isSessionValidated = false;
  String? _accessToken;
  Future<void>? _initializeFuture;
  Future<void> _mutationTail = Future<void>.value();

  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get isSessionValidated => _isSessionValidated;
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
        // A persisted token is only a candidate session. Boot must validate
        // it through the control plane before VPN restoration is allowed.
        _isSessionValidated = false;
      } else {
        _isSessionValidated = true;
      }
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setSession({required String accessToken, String? refreshToken}) {
    return _enqueueMutation(() async {
      await ensureInitialized();
      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      _accessToken = accessToken;
      _isAuthenticated = true;
      // A fresh login/register response is already an authenticated API
      // result, so it is safe for explicitly requested VPN work.
      _isSessionValidated = true;
      notifyListeners();
    });
  }

  Future<void> clearSession() {
    return _enqueueMutation(() async {
      await ensureInitialized();
      _accessToken = null;
      _isAuthenticated = false;
      _isSessionValidated = true;
      await _storage.clearTokens();
      notifyListeners();
    });
  }

  void markSessionValidated() {
    if (!_isAuthenticated || _isSessionValidated) return;
    _isSessionValidated = true;
    notifyListeners();
  }

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final completer = Completer<void>();
    final previous = _mutationTail;
    _mutationTail = completer.future;
    unawaited(() async {
      try {
        await previous;
      } catch (_) {
        // A failed storage mutation must not block a later explicit logout or
        // login attempt.
      }
      try {
        await mutation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }
}
