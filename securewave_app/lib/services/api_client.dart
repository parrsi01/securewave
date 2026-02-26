import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_plan.dart';
import '../core/services/auth_session.dart';
import '../core/models/vpn_profile.dart';
import '../core/models/vpn_protocol.dart';
import '../core/models/vpn_protocol_catalog.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authSessionProvider);
  return ApiClient(config, session: session);
});

class ApiClient {
  ApiClient(this._config, {AuthSession? session, Dio? dio}) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: _config.apiBaseUrl,
            headers: {'Content-Type': 'application/json'},
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
    AppLogger.info('ApiClient: initialized with baseUrl=${_config.apiBaseUrl}');
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

  static const Duration _serversCacheTtl = Duration(minutes: 5);
  static const Duration _planCacheTtl = Duration(minutes: 2);

  Future<Map<String, dynamic>> fetchHealth({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/health',
        cancelToken: cancelToken,
      );
      return response.data ?? const <String, dynamic>{};
    } catch (error, stackTrace) {
      AppLogger.error(
        'Health check error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<ServerRegion>> fetchServers({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedServers != null && _serversFetchedAt != null) {
      final age = DateTime.now().difference(_serversFetchedAt!);
      if (age < _serversCacheTtl) {
        return _cachedServers!;
      }
    }
    try {
      Future<List<ServerRegion>> fetchFrom(String path, String listKey) async {
        final response = await _dio.get<Map<String, dynamic>>(path);
        final data = response.data ?? <String, dynamic>{};
        final rawList =
            data[listKey] is List ? data[listKey] as List : <dynamic>[];
        return rawList
            .whereType<Map>()
            .map((entry) =>
                ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
            .toList();
      }

      List<ServerRegion> servers;
      String sourcePath;
      try {
        servers = await fetchFrom('/vpn/regions', 'regions');
        sourcePath = '/vpn/regions';
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status != 404 && status != 405) rethrow;
        servers = await fetchFrom('/vpn/servers', 'servers');
        sourcePath = '/vpn/servers';
      }

      AppLogger.info(
        'VPN servers fetched: count=${servers.length} source=$sourcePath baseUrl=${_config.apiBaseUrl} sample=${servers.take(5).map((s) => s.name).join(", ")}',
      );
      _cachedServers = servers;
      _serversFetchedAt = DateTime.now();
      return servers;
    } catch (error, stackTrace) {
      AppLogger.error('Server list error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<UserPlan> fetchUserPlan({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPlan != null && _planFetchedAt != null) {
      final age = DateTime.now().difference(_planFetchedAt!);
      if (age < _planCacheTtl) {
        return _cachedPlan!;
      }
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/user/plan');
      final data = response.data ?? <String, dynamic>{};
      final plan = UserPlan.fromJson(data);
      _cachedPlan = plan;
      _planFetchedAt = DateTime.now();
      return plan;
    } catch (error, stackTrace) {
      AppLogger.error('Plan error', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<AuthTokens> login(
      {required String email, required String password}) async {
    try {
      final response =
          await _dio.post<Map<String, dynamic>>('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final data = response.data ?? <String, dynamic>{};
      final requires2fa = data['requires_2fa'] == true ||
          data['requires_2fa']?.toString().toLowerCase() == 'true';
      if (requires2fa) {
        throw StateError(
          'This account requires a 2FA code, but this login screen does not yet support TOTP.',
        );
      }
      final accessToken = data['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('Login response missing access_token');
      }
      return AuthTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Login error', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<AuthTokens?> register(
      {required String email, required String password}) async {
    try {
      final response =
          await _dio.post<Map<String, dynamic>>('/auth/register', data: {
        'email': email,
        'password': password,
        'password_confirm': password,
      });
      final data = response.data ?? <String, dynamic>{};
      if (data['access_token'] == null) return null;
      return AuthTokens(
        accessToken: data['access_token']?.toString() ?? '',
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Registration error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/vpn/profile',
        data: {
          if (deviceId != null && deviceId > 0) 'device_id': deviceId,
          'device_name': deviceName,
          'device_type': deviceType,
          if (protocol != VpnProtocol.auto)
            'protocol': vpnProtocolStorageValue(protocol),
          if (serverId != null && serverId.isNotEmpty) 'server_id': serverId,
          if (forceRotateKeys) 'force_rotate_keys': true,
        },
        cancelToken: cancelToken,
      );
      final data = response.data ?? <String, dynamic>{};
      return VpnProfile.fromJson(data);
    } catch (error, stackTrace) {
      AppLogger.error('VPN profile fetch failed',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<VpnProtocolCatalog> fetchVpnProtocols({
    required String deviceType,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/vpn/protocols',
        queryParameters: {
          if (deviceType.isNotEmpty && deviceType != 'unknown')
            'device_type': deviceType,
        },
        cancelToken: cancelToken,
      );
      final data = response.data ?? const <String, dynamic>{};
      final catalog = VpnProtocolCatalog.fromJson(data);
      final enabled = catalog
          .enabledProtocols()
          .map(vpnProtocolStorageValue)
          .toList()
        ..sort();
      AppLogger.info(
        'VPN protocols fetched: deviceType=$deviceType enabled=${enabled.join(",")} baseUrl=${_config.apiBaseUrl}',
      );
      return catalog;
    } catch (error, stackTrace) {
      AppLogger.error('VPN protocols fetch failed',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> fetchVpnMetricsSnapshot(
      {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/metrics/vpn',
        cancelToken: cancelToken,
      );
      return response.data;
    } catch (error, stackTrace) {
      AppLogger.warning('VPN metrics snapshot unavailable (non-fatal).');
      AppLogger.error('VPN metrics fetch error',
          error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// Notify the backend that the VPN tunnel has been established.
  Future<void> notifyVpnConnected({
    String? region,
    String? serverId,
    VpnProtocol? protocol,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (region != null && region.isNotEmpty) 'region': region,
        if (serverId != null && serverId.isNotEmpty) 'server_id': serverId,
        if (protocol != null && protocol != VpnProtocol.auto)
          'protocol': vpnProtocolStorageValue(protocol),
      };
      await _dio.post<Map<String, dynamic>>(
        '/vpn/connect',
        data: payload,
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Backend VPN connect notification failed (non-fatal).');
      AppLogger.error('VPN connect notify error',
          error: error, stackTrace: stackTrace);
    }
  }

  /// Notify the backend that the VPN tunnel has been torn down.
  Future<void> notifyVpnDisconnected() async {
    try {
      await _dio.post<Map<String, dynamic>>('/vpn/disconnect');
    } catch (error, stackTrace) {
      AppLogger.warning(
          'Backend VPN disconnect notification failed (non-fatal).');
      AppLogger.error('VPN disconnect notify error',
          error: error, stackTrace: stackTrace);
    }
  }
}

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}
