import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/server_region.dart';
import '../core/models/user_account.dart';
import '../core/models/user_plan.dart';
import '../core/models/vpn_profile.dart';
import '../core/services/auth_session.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(appConfigProvider),
    session: ref.watch(authSessionProvider),
  );
});

class ApiClient {
  ApiClient(this._config, {required AuthSession session, Dio? dio})
      : _session = session {
    _dio = dio ??
        Dio(BaseOptions(
            baseUrl: _config.apiBaseUrl,
            headers: const {'Content-Type': 'application/json'}));
    _dio.options.validateStatus = (_) => true;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _session.accessToken;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        if (response.statusCode == 401) await _session.clearSession();
        if ((response.statusCode ?? 0) >= 400) {
          handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: 'HTTP ${response.statusCode}'));
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
      return const UserAccount(
          id: 1, email: 'demo@securewave.local', isActive: true);
    }
    final response = await _dio.get<Map<String, dynamic>>('/auth/me');
    return UserAccount.fromJson(response.data ?? const {});
  }

  Future<SecureWaveTarget> fetchTarget() async {
    if (_config.demoMode) {
      return const SecureWaveTarget(
        id: 'demo',
        name: 'SecureWave Beta',
        location: 'Simulated target',
        health: 'healthy',
        protocol: 'wireguard',
      );
    }
    final response = await _dio.get<Map<String, dynamic>>('/vpn/target');
    return SecureWaveTarget.fromJson(response.data ?? const {});
  }

  Future<List<ServerRegion>> fetchServers() async {
    final target = await fetchTarget();
    return <ServerRegion>[target.toServerRegion()];
  }

  Future<UserPlan> fetchUserPlan() async {
    if (_config.demoMode) {
      return const UserPlan(
        name: 'Free',
        isPremium: false,
        dataCapGb: 5,
        usedGb: 1.6,
      );
    }
    final response = await _dio.get<Map<String, dynamic>>('/user/plan');
    return UserPlan.fromJson(response.data ?? const {});
  }

  Future<AuthTokens> login(
      {required String email, required String password}) async {
    if (_config.demoMode) return _demoTokens(email);
    final response = await _dio.post<Map<String, dynamic>>('/auth/login',
        data: {'email': email, 'password': password});
    return _tokensFromResponse(response.data);
  }

  Future<AuthTokens> register(
      {required String email, required String password}) async {
    if (_config.demoMode) return _demoTokens(email);
    final response = await _dio.post<Map<String, dynamic>>('/auth/register',
        data: {'email': email, 'password': password});
    return _tokensFromResponse(response.data);
  }

  Future<VpnProfile> fetchVpnProfile(
      {required String deviceName,
      required String deviceType,
      int? deviceId}) async {
    if (_config.demoMode) {
      return const VpnProfile(
          deviceId: 1,
          deviceName: 'Demo Linux',
          deviceType: 'linux',
          serverId: 'demo',
          serverLocation: 'Simulated target',
          wireguardConfig: '# DEMO ONLY\n');
    }
    final response =
        await _dio.post<Map<String, dynamic>>('/vpn/profile', data: {
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
    if (token == null || token.isEmpty) {
      throw StateError(
          'Authentication response did not include an access token.');
    }
    return AuthTokens(accessToken: token);
  }

  AuthTokens _demoTokens(String email) =>
      AuthTokens(accessToken: 'demo-session-${email.trim().toLowerCase()}');
}

class AuthTokens {
  const AuthTokens({required this.accessToken});

  final String accessToken;
}

class SecureWaveTarget {
  const SecureWaveTarget({
    required this.id,
    required this.name,
    required this.location,
    required this.health,
    required this.protocol,
    this.city,
    this.country,
    this.latencyMs,
    this.loadPercent,
  });

  final String id;
  final String name;
  final String location;
  final String health;
  final String protocol;
  final String? city;
  final String? country;
  final int? latencyMs;
  final double? loadPercent;

  factory SecureWaveTarget.fromJson(Map<String, dynamic> json) {
    final latency = json['latency_ms'];
    final load = json['load_percent'];
    return SecureWaveTarget(
      id: json['server_id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'SecureWave Beta',
      location: json['location']?.toString().trim().isNotEmpty == true
          ? json['location'].toString().trim()
          : 'SecureWave Beta',
      health: json['health']?.toString().trim().isNotEmpty == true
          ? json['health'].toString().trim()
          : 'unknown',
      protocol: json['protocol']?.toString().trim().toLowerCase() ?? '',
      city: _optionalString(json['city']),
      country: _optionalString(json['country']),
      latencyMs: latency is num ? latency.round() : null,
      loadPercent: load is num && load.isFinite ? load.toDouble() : null,
    );
  }

  ServerRegion toServerRegion() => ServerRegion(
        id: id,
        name: name,
        location: location,
        city: city,
        country: country,
        latencyMs: latencyMs,
        loadPercent: loadPercent,
        health: health,
        supportedProtocols:
            protocol == 'wireguard' ? const <String>['wireguard'] : const [],
      );

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
