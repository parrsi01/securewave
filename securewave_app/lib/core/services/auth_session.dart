import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'secure_storage.dart';

final authSessionProvider = ChangeNotifierProvider<AuthSession>((ref) {
  return AuthSession();
});

class AuthSession extends ChangeNotifier {
  AuthSession({
    SecureStorage? storage,
    DateTime Function()? clock,
    Duration storageTimeout = const Duration(seconds: 2),
  })  : _storage = storage ?? SecureStorage(),
        _clock = clock ?? DateTime.now,
        _storageTimeout = storageTimeout {
    _initializationFuture = _initializeSession();
  }

  final SecureStorage _storage;
  final DateTime Function() _clock;
  final Duration _storageTimeout;
  late final Future<void> _initializationFuture;

  bool _isAuthenticated = false;
  String? _accessToken;
  String? _email;

  bool get isAuthenticated => _isAuthenticated;
  String? get accessToken => _accessToken;
  String? get email => _email;

  /// Returns true when an access token is present and is not near expiry.
  ///
  /// Opaque/non-JWT tokens are treated as fresh because expiry cannot be
  /// verified client-side.
  bool hasFreshAccessToken({
    Duration minValidity = const Duration(seconds: 60),
  }) {
    return accessTokenFreshnessIssue(minValidity: minValidity) == null;
  }

  /// Returns a machine-readable reason when the token should not be used for
  /// auto-connect/authenticated control-plane calls.
  String? accessTokenFreshnessIssue({
    Duration minValidity = const Duration(seconds: 60),
  }) {
    final token = _accessToken?.trim();
    if (token == null || token.isEmpty) {
      return 'missing_access_token';
    }
    if (!_looksLikeJwt(token)) {
      return null;
    }
    final expiry = _jwtExpiry(token);
    if (expiry == null) {
      return 'invalid_jwt_or_missing_exp';
    }
    final cutoff = _clock().toUtc().add(minValidity);
    if (!expiry.isAfter(cutoff)) {
      return 'expiring_or_expired_jwt';
    }
    return null;
  }

  /// Completes when the session has been initialized from secure storage.
  ///
  /// Awaited by [BootController] to ensure auth state is stable before the
  /// router evaluates redirect guards. Exposed publicly (not just for tests)
  /// because the boot sequence is production code that must await it.
  Future<void> get initializationComplete => _initializationFuture;

  Future<void> _initializeSession() async {
    try {
      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null || token.trim().isEmpty) {
        notifyListeners();
        return;
      }

      final validation = _validateAccessToken(token);
      if (validation != null) {
        AppLogger.warning(
          'Auth session restore rejected token: $validation',
        );
        await _clearPersistedSessionArtifacts();
        notifyListeners();
        return;
      }

      _accessToken = token;
      final email = await _storage.getSessionEmail().timeout(_storageTimeout);
      _email = (email == null || email.trim().isEmpty) ? null : email.trim();
      _isAuthenticated = true;
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.error(
        'Auth session restore timed out',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Auth session restore failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    notifyListeners();
  }

  Future<void> setSession(
      {required String accessToken,
      String? refreshToken,
      String? email}) async {
    final validation =
        _looksLikeJwt(accessToken) ? _validateAccessToken(accessToken) : null;
    if (validation != null) {
      throw StateError('Cannot persist invalid access token: $validation');
    }
    _accessToken = accessToken;
    final normalizedEmail = email?.trim();
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      _email = normalizedEmail;
    }
    _isAuthenticated = true;
    AppLogger.debug(
      '[AUTH_DIAG] {"event":"session_set_start","has_email":'
      '${normalizedEmail != null && normalizedEmail.isNotEmpty},'
      '"has_refresh":${refreshToken != null && refreshToken.isNotEmpty}}',
      tag: 'SecureWave.Auth',
    );
    try {
      final writes = <Future<void>>[
        _storage.saveTokens(
            accessToken: accessToken, refreshToken: refreshToken),
      ];
      if (_email != null && _email!.trim().isNotEmpty) {
        writes.add(_storage.saveSessionEmail(_email!.trim()));
      }
      await Future.wait<void>(writes).timeout(_storageTimeout);
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.warning(
        'Auth token persistence timed out; continuing with in-memory session.',
      );
      AppLogger.error(
        'Auth token persistence timed out',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Auth token persistence failed; continuing with in-memory session.',
      );
      AppLogger.error(
        'Auth token persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    AppLogger.debug(
      '[AUTH_DIAG] {"event":"session_set_done","authenticated":true}',
      tag: 'SecureWave.Auth',
    );
    notifyListeners();
  }

  /// Read the persisted refresh token (for 401 token refresh flow).
  Future<String?> getRefreshToken() => _storage.getRefreshToken();

  /// Update the cached email (e.g. after a successful email change).
  void updateEmail(String newEmail) {
    _email = newEmail;
    notifyListeners();
  }

  Future<void> clearSession() async {
    AppLogger.debug(
      '[AUTH_DIAG] {"event":"session_clear_start"}',
      tag: 'SecureWave.Auth',
    );
    _accessToken = null;
    _email = null;
    _isAuthenticated = false;
    await _clearPersistedSessionArtifacts();
    AppLogger.debug(
      '[AUTH_DIAG] {"event":"session_clear_done"}',
      tag: 'SecureWave.Auth',
    );
    notifyListeners();
  }

  Future<void> _clearPersistedSessionArtifacts() async {
    await Future.wait<void>([
      _storage.clearTokens(),
      _storage.delete(SecureStorage.sessionEmailKey),
      _storage.delete(SecureStorage.vpnProfileConfigKey),
      _storage.delete(SecureStorage.vpnProfileExpiresAtKey),
      _storage.delete(SecureStorage.vpnDeviceIdKey),
    ]).timeout(_storageTimeout);
  }

  String? _validateAccessToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return 'empty_token';

    final expiry = _jwtExpiry(trimmed);
    if (expiry == null) return 'invalid_jwt_or_missing_exp';

    // Small skew protects against near-expiry race conditions during startup.
    final nowWithSkew = _clock().toUtc().add(const Duration(seconds: 30));
    if (!expiry.isAfter(nowWithSkew)) {
      return 'expired_jwt';
    }
    return null;
  }

  bool _looksLikeJwt(String token) => token.split('.').length == 3;

  DateTime? _jwtExpiry(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final rawExp = decoded['exp'];
      final expSeconds = switch (rawExp) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      if (expSeconds == null || expSeconds <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        expSeconds * 1000,
        isUtc: true,
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Auth token parse failed');
      AppLogger.error(
        'Auth token parse failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
