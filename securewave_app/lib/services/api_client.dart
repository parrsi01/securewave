import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_plan.dart';
import '../core/services/auth_session.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authSessionProvider);
  return ApiClient(config, session: session);
});

class ApiClient {
  ApiClient(this._config, {AuthSession? session}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _config.apiBaseUrl,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    if (session != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final token = session.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            return handler.next(options);
          },
        ),
      );
    }
  }

  final AppConfig _config;
  late final Dio _dio;
  List<ServerRegion>? _cachedServers;
  DateTime? _serversFetchedAt;
  UserPlan? _cachedPlan;
  DateTime? _planFetchedAt;
  bool _mockNoticeLogged = false;

  static const Duration _serversCacheTtl = Duration(minutes: 5);
  static const Duration _planCacheTtl = Duration(minutes: 2);

  Future<List<ServerRegion>> fetchServers({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedServers != null && _serversFetchedAt != null) {
      final age = DateTime.now().difference(_serversFetchedAt!);
      if (age < _serversCacheTtl) {
        return _cachedServers!;
      }
    }
    if (_config.useMockApi) {
      _logMockApi();
      final data = _mockServers();
      _cachedServers = data;
      _serversFetchedAt = DateTime.now();
      return data;
    }
    try {
      final response = await _dio.get<List<dynamic>>('/vpn/servers');
      final data = response.data ?? <dynamic>[];
      final servers = data
          .whereType<Map>()
          .map((entry) => ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      _cachedServers = servers;
      _serversFetchedAt = DateTime.now();
      return servers;
    } catch (error, stackTrace) {
      AppLogger.warning('Server list unavailable, using mock regions.');
      AppLogger.error('Server list error', error: error, stackTrace: stackTrace);
      final data = _mockServers();
      _cachedServers = data;
      _serversFetchedAt = DateTime.now();
      return data;
    }
  }

  Future<UserPlan> fetchUserPlan({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPlan != null && _planFetchedAt != null) {
      final age = DateTime.now().difference(_planFetchedAt!);
      if (age < _planCacheTtl) {
        return _cachedPlan!;
      }
    }
    if (_config.useMockApi) {
      _logMockApi();
      final plan = _mockPlan();
      _cachedPlan = plan;
      _planFetchedAt = DateTime.now();
      return plan;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/user/plan');
      final data = response.data ?? <String, dynamic>{};
      final plan = UserPlan.fromJson(data);
      _cachedPlan = plan;
      _planFetchedAt = DateTime.now();
      return plan;
    } catch (error, stackTrace) {
      AppLogger.warning('Plan lookup failed, using mock plan.');
      AppLogger.error('Plan error', error: error, stackTrace: stackTrace);
      final plan = _mockPlan();
      _cachedPlan = plan;
      _planFetchedAt = DateTime.now();
      return plan;
    }
  }

  Future<AuthTokens> login({required String email, required String password}) async {
    if (_config.useMockApi) {
      _logMockApi();
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
      _logMockApi();
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

  Future<String> fetchVpnConfig({String? serverId}) async {
    if (_config.useMockApi) {
      _logMockApi();
      return _mockVpnConfig();
    }
    Map<String, dynamic>? payload;
    if (serverId != null && serverId.isNotEmpty) {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/vpn/allocate',
          data: {'server_id': serverId},
        );
        payload = response.data;
      } catch (error, stackTrace) {
        AppLogger.warning('VPN allocation failed, falling back to existing config.');
        AppLogger.error('VPN allocation error', error: error, stackTrace: stackTrace);
      }
    }
    try {
      final response = payload == null
          ? await _dio.get<Map<String, dynamic>>('/vpn/config')
          : null;
      final data = payload ?? response?.data ?? <String, dynamic>{};
      final config = data['config'];
      if (config is String && config.trim().isNotEmpty) {
        return config;
      }
      throw StateError('VPN configuration missing from response.');
    } catch (error, stackTrace) {
      AppLogger.error('VPN config fetch failed', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  void _logMockApi() {
    if (_mockNoticeLogged) return;
    _mockNoticeLogged = true;
    AppLogger.warning('Mock API enabled: returning demo data instead of live endpoints.');
  }

  String _mockVpnConfig() {
    return '''
[Interface]
PrivateKey = DEMO_PRIVATE_KEY
Address = 10.10.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = DEMO_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = demo.securewave.invalid:51820
''';
  }
}

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}
