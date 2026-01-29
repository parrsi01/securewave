import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_plan.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(config);
});

class ApiClient {
  ApiClient(this._config) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _config.apiBaseUrl,
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  final AppConfig _config;
  late final Dio _dio;

  Future<List<ServerRegion>> fetchServers() async {
    if (_config.useMockApi) {
      return _mockServers();
    }
    try {
      final response = await _dio.get<List<dynamic>>('/vpn/servers');
      final data = response.data ?? <dynamic>[];
      return data
          .whereType<Map>()
          .map((entry) => ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.warning('Server list unavailable, using mock regions.');
      AppLogger.error('Server list error', error: error, stackTrace: stackTrace);
      return _mockServers();
    }
  }

  Future<UserPlan> fetchUserPlan() async {
    if (_config.useMockApi) {
      return _mockPlan();
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/user/plan');
      final data = response.data ?? <String, dynamic>{};
      return UserPlan.fromJson(data);
    } catch (error, stackTrace) {
      AppLogger.warning('Plan lookup failed, using mock plan.');
      AppLogger.error('Plan error', error: error, stackTrace: stackTrace);
      return _mockPlan();
    }
  }

  Future<AuthTokens> login({required String email, required String password}) async {
    if (_config.useMockApi) {
      return _mockTokens(email);
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = response.data ?? <String, dynamic>{};
      return AuthTokens(
        accessToken: data['access_token']?.toString() ?? 'mock-access-token',
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Login failed, returning mock token.');
      AppLogger.error('Login error', error: error, stackTrace: stackTrace);
      return _mockTokens(email);
    }
  }

  Future<AuthTokens?> register({required String email, required String password}) async {
    if (_config.useMockApi) {
      return _mockTokens(email);
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>('/auth/register', data: {
        'email': email,
        'password': password,
        'password_confirm': password,
      });
      final data = response.data ?? <String, dynamic>{};
      if (data['access_token'] == null) return null;
      return AuthTokens(
        accessToken: data['access_token']?.toString() ?? 'mock-access-token',
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Registration failed, returning mock token.');
      AppLogger.error('Registration error', error: error, stackTrace: stackTrace);
      return _mockTokens(email);
    }
  }

  AuthTokens _mockTokens(String email) {
    final handle = email.split('@').first;
    return AuthTokens(accessToken: 'mock-token-$handle', refreshToken: 'mock-refresh-$handle');
  }

  List<ServerRegion> _mockServers() {
    return const [
      ServerRegion(id: 'us-chi', name: 'Chicago, IL', country: 'United States', latencyMs: 28),
      ServerRegion(id: 'us-nyc', name: 'New York, NY', country: 'United States', latencyMs: 42),
      ServerRegion(id: 'uk-lon', name: 'London', country: 'United Kingdom', latencyMs: 75),
      ServerRegion(id: 'de-fra', name: 'Frankfurt', country: 'Germany', latencyMs: 58),
      ServerRegion(id: 'sg-sin', name: 'Singapore', country: 'Singapore', latencyMs: 91),
    ];
  }

  UserPlan _mockPlan() {
    return const UserPlan(
      name: 'Free',
      isPremium: false,
      dataCapGb: 5,
      usedGb: 1.6,
    );
  }
}

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}
