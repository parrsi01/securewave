import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const autoConnectKey = 'pref_auto_connect';
  static const selectedServerKey = 'selected_server_id';
  static const resetSessionDoneKey = 'reset_session_done';
  static const vpnProtocolKey = 'vpn_protocol';
  static const deviceInstallIdKey = 'device_install_id';
  static const deviceNameKey = 'device_name';
  static const vpnDeviceIdKey = 'vpn_device_id';
  static const vpnProfileConfigKey = 'vpn_profile_wireguard_config';
  static const vpnProfileExpiresAtKey = 'vpn_profile_expires_at';
  static const recentLoginEmailsKey = 'recent_login_emails';

  Future<void> saveTokens(
      {required String accessToken, String? refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> saveString(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> getString(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> saveBool(String key, bool value) =>
      _storage.write(key: key, value: value.toString());

  Future<bool?> getBool(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    return raw.toLowerCase() == 'true';
  }

  Future<void> saveInt(String key, int value) =>
      _storage.write(key: key, value: value.toString());

  Future<int?> getInt(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<List<String>> getRecentLoginEmails() async {
    final raw = await _storage.read(key: recentLoginEmailsKey);
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty && item.contains('@'))
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> saveRecentLoginEmail(
    String email, {
    int maxEntries = 6,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) return;
    final existing = await getRecentLoginEmails();
    final next = <String>[
      normalized,
      ...existing.where((entry) => entry != normalized),
    ];
    if (next.length > maxEntries) {
      next.removeRange(maxEntries, next.length);
    }
    await _storage.write(
      key: recentLoginEmailsKey,
      value: jsonEncode(next),
    );
  }
}
