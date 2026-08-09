import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.demoMode ? DemoSecureStorage() : SecureStorage();
});

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const vpnDeviceIdKey = 'vpn_device_id';
  static const selectedServerKey = 'vpn_selected_server_id';

  Future<void> saveToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> clearToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  Future<void> clearVpnRuntimeState() async {
    await _storage.delete(key: vpnDeviceIdKey);
    await _storage.delete(key: selectedServerKey);
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

class DemoSecureStorage extends SecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> saveToken(String accessToken) =>
      saveString(SecureStorage._accessTokenKey, accessToken);

  @override
  Future<String?> getAccessToken() => getString(SecureStorage._accessTokenKey);

  @override
  Future<void> clearToken() => delete(SecureStorage._accessTokenKey);

  @override
  Future<void> clearVpnRuntimeState() async {
    await delete(SecureStorage.vpnDeviceIdKey);
    await delete(SecureStorage.selectedServerKey);
  }

  @override
  Future<void> saveString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> saveBool(String key, bool value) =>
      saveString(key, value.toString());

  @override
  Future<bool?> getBool(String key) async {
    final raw = await getString(key);
    return raw == null ? null : raw.toLowerCase() == 'true';
  }

  @override
  Future<void> saveInt(String key, int value) =>
      saveString(key, value.toString());

  @override
  Future<int?> getInt(String key) async =>
      int.tryParse(await getString(key) ?? '');
}
