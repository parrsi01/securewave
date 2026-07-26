import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const selectedServerKey = 'selected_server_id';
  static const resetSessionDoneKey = 'reset_session_done';
  static const accountOwnerEmailKey = 'account_owner_email';
  static const vpnProtocolKey = 'vpn_protocol';
  static const deviceInstallIdKey = 'device_install_id';
  static const deviceNameKey = 'device_name';
  static const vpnDeviceIdKey = 'vpn_device_id';
  static const vpnActiveServerIdKey = 'vpn_active_server_id';
  static const vpnProfileConfigKey = 'vpn_profile_wireguard_config';
  static const vpnProfileExpiresAtKey = 'vpn_profile_expires_at';

  static String vpnProfileConfigKeyFor(String protocol) {
    return 'vpn_profile_${protocol}_config';
  }

  Future<void> saveTokens(
      {required String accessToken, String? refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    } else {
      // A login response without a refresh token must not leave a previous
      // account's refresh credential behind.
      await _storage.delete(key: _refreshTokenKey);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<String?> getAccountOwnerEmail() =>
      _storage.read(key: accountOwnerEmailKey);

  Future<void> saveAccountOwnerEmail(String email) =>
      _storage.write(key: accountOwnerEmailKey, value: email);

  Future<void> clearAccountOwnerEmail() =>
      _storage.delete(key: accountOwnerEmailKey);

  Future<void> clearVpnRuntimeState() async {
    await _storage.delete(key: selectedServerKey);
    await _storage.delete(key: vpnDeviceIdKey);
    await _storage.delete(key: vpnActiveServerIdKey);
    await _storage.delete(key: vpnProfileExpiresAtKey);
    await _storage.delete(key: vpnProfileConfigKeyFor('wireguard'));
    await _storage.delete(key: vpnProfileConfigKeyFor('openvpn'));
    await _storage.delete(key: vpnProfileConfigKeyFor('ikev2'));
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
