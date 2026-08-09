import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/user_account.dart';
import '../core/models/vpn_profile.dart';
import '../core/services/auth_session.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(appConfigProvider),
    session: ref.watch(authSessionProvider),
  );
});

class ApiClient {
  ApiClient(this._config, {required AuthSession session, Dio? dio}) : _session = session {
    _dio = dio ?? Dio(BaseOptions(baseUrl: _config.apiBaseUrl, headers: const {'Content-Type': 'application/json'}));
    _dio.options.validateStatus = (_) => true;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _session.accessToken;
        if (token != null && token.isNotEmpty) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onResponse: (response, handler) async {
        if (response.statusCode == 401) await _session.clearSession();
        if ((response.statusCode ?? 0) >= 400) {
          handler.reject(DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse, message: 'HTTP ${response.statusCode}'));
          return;
        }
        handler.next(response);
      },
    ));
  }

  final AppConfig _config;
  final AuthSession _session;
  late final Dio _dio;

  Future<UserAccount> fetchCurrentUser() async {
    if (_config.demoMode) {
      return const UserAccount(id: 1, email: 'demo@securewave.local', isActive: true);
    }
    final response = await _dio.get<Map<String, dynamic>>('/auth/me');
    return UserAccount.fromJson(response.data ?? const {});
  }

  Future<SecureWaveTarget> fetchTarget() async {
    if (_config.demoMode) return const SecureWaveTarget(name: 'SecureWave Beta', location: 'Simulated target', health: 'healthy');
    final response = await _dio.get<Map<String, dynamic>>('/vpn/target');
    return SecureWaveTarget.fromJson(response.data ?? const {});
  }

  Future<AuthTokens> login({required String email, required String password}) async {
    if (_config.demoMode) return _demoTokens(email);
    final response = await _dio.post<Map<String, dynamic>>('/auth/login', data: {'email': email, 'password': password});
    return _tokensFromResponse(response.data);
  }

  Future<AuthTokens> register({required String email, required String password}) async {
    if (_config.demoMode) return _demoTokens(email);
    final response = await _dio.post<Map<String, dynamic>>('/auth/register', data: {'email': email, 'password': password});
    return _tokensFromResponse(response.data);
  }

  Future<VpnProfile> fetchVpnProfile({required String deviceName, required String deviceType, int? deviceId}) async {
    if (_config.demoMode) {
      return const VpnProfile(deviceId: 1, deviceName: 'Demo Linux', deviceType: 'linux', serverId: 'demo', serverLocation: 'Simulated target', wireguardConfig: '# DEMO ONLY\n');
    }
    final response = await _dio.post<Map<String, dynamic>>('/vpn/profile', data: {
      'device_name': deviceName,
      'device_type': deviceType,
      if (deviceId != null) 'device_id': deviceId,
    });
    return VpnProfile.fromJson(response.data ?? const {});
  }

  Future<void> logout() async {
    if (_config.demoMode) return;
    await _dio.post<Map<String, dynamic>>('/auth/logout');
  }

  AuthTokens _tokensFromResponse(Map<String, dynamic>? data) {
    final token = data?['access_token']?.toString();
    if (token == null || token.isEmpty) throw StateError('Authentication response did not include an access token.');
    return AuthTokens(accessToken: token);
  }

  AuthTokens _demoTokens(String email) => AuthTokens(accessToken: 'demo-session-${email.trim().toLowerCase()}');
}

class AuthTokens {
  const AuthTokens({required this.accessToken});

  final String accessToken;
}

class SecureWaveTarget {
  const SecureWaveTarget({required this.name, required this.location, required this.health});

  final String name;
  final String location;
  final String health;

  factory SecureWaveTarget.fromJson(Map<String, dynamic> json) => SecureWaveTarget(
    name: json['name']?.toString() ?? 'SecureWave Beta',
    location: json['location']?.toString() ?? 'SecureWave Beta',
    health: json['health']?.toString() ?? 'unknown',
  );
}
