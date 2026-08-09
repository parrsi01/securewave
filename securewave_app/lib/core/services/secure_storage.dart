import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const vpnDeviceIdKey = 'vpn_device_id';

  Future<void> saveToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> clearToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  Future<void> clearVpnRuntimeState() async {
    await _storage.delete(key: vpnDeviceIdKey);
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
}
