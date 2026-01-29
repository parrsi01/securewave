import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const selectedServerKey = 'selected_server_id';
  static const adblockAdsKey = 'adblock_ads';
  static const adblockMalwareKey = 'adblock_malware';
  static const adblockStrictKey = 'adblock_strict';
  static const adblockUpdatedKey = 'adblock_updated_at';
  static const adblockRulesKey = 'adblock_rules_count';
  static const resetSessionDoneKey = 'reset_session_done';

  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
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

  Future<void> saveString(String key, String value) => _storage.write(key: key, value: value);

  Future<String?> getString(String key) => _storage.read(key: key);

  Future<void> saveBool(String key, bool value) => _storage.write(key: key, value: value.toString());

  Future<bool?> getBool(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    return raw.toLowerCase() == 'true';
  }

  Future<void> saveInt(String key, int value) => _storage.write(key: key, value: value.toString());

  Future<int?> getInt(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    return int.tryParse(raw);
  }
}
