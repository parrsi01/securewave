import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
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

    // In non-release builds, allow self-signed certificates so the dev VPS
    // (which uses a self-signed cert on an IP address) remains reachable.
    // This path is never compiled into release builds.
    if (!kReleaseMode && _dio.httpClientAdapter is IOHttpClientAdapter) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          AppLogger.warning(
            'ApiClient: accepting self-signed cert for $host:$port '
            '(dev/debug only — never in release)',
          );
          return true;
        };
        return client;
      };
    }

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
          onError: (error, handler) async {
            if (error.response?.statusCode != 401) {
              return handler.next(error);
            }
            // Prevent infinite loop: if this is already a retry, give up.
            if (error.requestOptions.extra['_isRetry'] == true) {
              return handler.next(error);
            }
            try {
              final refreshToken = await session.getRefreshToken();
              if (refreshToken == null || refreshToken.isEmpty) {
                debugPrint(
                    '[AUTH_REFRESH] no refresh token — clearing session');
                await session.clearSession();
                return handler.next(error);
              }
              debugPrint(
                  '[AUTH_REFRESH] 401 received — attempting token refresh');
              // Use a plain Dio (no interceptors) to avoid re-entry.
              final refreshDio = Dio(BaseOptions(
                baseUrl: _config.apiBaseUrl,
                headers: {'Content-Type': 'application/json'},
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ));
              if (!kReleaseMode &&
                  refreshDio.httpClientAdapter is IOHttpClientAdapter) {
                (refreshDio.httpClientAdapter as IOHttpClientAdapter)
                    .createHttpClient = () {
                  final client = HttpClient();
                  client.badCertificateCallback = (_, __, ___) => true;
                  return client;
                };
              }
              final refreshResp = await refreshDio.post<Map<String, dynamic>>(
                '/auth/refresh',
                data: {'refresh_token': refreshToken},
              );
              final newAccess = refreshResp.data?['access_token']?.toString();
              final newRefresh = refreshResp.data?['refresh_token']?.toString();
              if (newAccess == null || newAccess.isEmpty) {
                debugPrint(
                    '[AUTH_REFRESH] refresh response missing access_token');
                await session.clearSession();
                return handler.next(error);
              }
              await session.setSession(
                accessToken: newAccess,
                refreshToken: newRefresh,
              );
              debugPrint('[AUTH_REFRESH] tokens refreshed — retrying request');
              // Retry the original request with the new token.
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newAccess';
              opts.extra['_isRetry'] = true;
              final retryResp = await _dio.fetch(opts);
              return handler.resolve(retryResp);
            } catch (refreshError) {
              debugPrint(
                  '[AUTH_REFRESH] refresh failed: $refreshError — clearing session');
              await session.clearSession();
              return handler.next(error);
            }
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
  static const bool _strictContractValidation = !kReleaseMode;

  Never _contractViolation(String endpoint, String detail) {
    throw StateError('API contract violation at $endpoint: $detail');
  }

  bool _isBoolLike(Object? value) {
    if (value is bool) return true;
    if (value is num) return true;
    if (value == null) return false;
    final text = value.toString().trim().toLowerCase();
    return text == 'true' || text == 'false' || text == '1' || text == '0';
  }

  bool _isNumLike(Object? value) {
    if (value is num) return true;
    if (value == null) return false;
    return num.tryParse(value.toString()) != null;
  }

  String? _responseHeader(Headers? headers, String name) {
    if (headers == null) return null;
    final values = headers.map[name] ??
        headers.map[name.toLowerCase()] ??
        headers.map[name.toUpperCase()];
    if (values == null || values.isEmpty) return null;
    final value = values.first.trim();
    return value.isEmpty ? null : value;
  }

  String? _extractApiErrorCode(Object? data) {
    if (data is! Map) return null;
    final payload = data['error'];
    if (payload is! Map) return null;
    final code = payload['code']?.toString().trim();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  String? _extractApiErrorMessage(Object? data) {
    if (data is! Map) return null;
    final payload = data['error'];
    if (payload is! Map) return null;
    final message = payload['message']?.toString().trim();
    if (message == null || message.isEmpty) return null;
    return message;
  }

  void _validateUsageContract(Map<String, dynamic> usage) {
    const endpoint = '/account/usage';
    final required = <String, String>{
      'quota_bytes': 'number',
      'used_bytes': 'number',
      'used_percent': 'number',
      'plan_tier': 'string',
      'devices_count': 'number',
      'username': 'string',
      'display_name': 'string',
    };
    for (final entry in required.entries) {
      if (!usage.containsKey(entry.key)) {
        _contractViolation(endpoint, 'missing key `${entry.key}`');
      }
    }
    if (!_isNumLike(usage['quota_bytes'])) {
      _contractViolation(endpoint, '`quota_bytes` must be numeric');
    }
    if (!_isNumLike(usage['used_bytes'])) {
      _contractViolation(endpoint, '`used_bytes` must be numeric');
    }
    if (!_isNumLike(usage['used_percent'])) {
      _contractViolation(endpoint, '`used_percent` must be numeric');
    }
    if (usage['plan_tier'] == null || usage['plan_tier'].toString().isEmpty) {
      _contractViolation(endpoint, '`plan_tier` must be non-empty string');
    }
    if (!_isNumLike(usage['devices_count'])) {
      _contractViolation(endpoint, '`devices_count` must be numeric');
    }
  }

  void _validateRegionsContract(
    Map<String, dynamic> payload,
    List<dynamic> rawList,
  ) {
    const endpoint = '/vpn/regions';
    if (!payload.containsKey('regions') || payload['regions'] is! List) {
      _contractViolation(endpoint, '`regions` list is required');
    }
    for (var index = 0; index < rawList.length; index++) {
      final raw = rawList[index];
      if (raw is! Map) {
        _contractViolation(endpoint, 'region[$index] must be object');
      }
      final item = Map<String, dynamic>.from(raw);
      const requiredKeys = <String>[
        'server_id',
        'region_health_status',
        'region_health_last_checked_at',
        'region_health_reason_code',
      ];
      for (final key in requiredKeys) {
        if (!item.containsKey(key)) {
          _contractViolation(endpoint, 'region[$index] missing `$key`');
        }
      }
      final health = item['region_health_status']?.toString().toLowerCase();
      if (health != 'up' && health != 'down' && health != 'unknown') {
        _contractViolation(
          endpoint,
          'region[$index] `region_health_status` invalid: $health',
        );
      }
    }
  }

  void _validateProtocolsContract(Map<String, dynamic> payload) {
    const endpoint = '/vpn/protocols';
    final protocols = payload['protocols'];
    if (protocols is! List) {
      _contractViolation(endpoint, '`protocols` list is required');
    }
    for (var index = 0; index < protocols.length; index++) {
      final raw = protocols[index];
      if (raw is! Map) {
        _contractViolation(endpoint, 'protocol[$index] must be object');
      }
      final item = Map<String, dynamic>.from(raw);
      const requiredKeys = <String>[
        'protocol',
        'enabled',
        'server_enabled',
        'plan_enabled',
        'platform_supported',
      ];
      for (final key in requiredKeys) {
        if (!item.containsKey(key)) {
          _contractViolation(endpoint, 'protocol[$index] missing `$key`');
        }
      }
      if (!_isBoolLike(item['enabled']) ||
          !_isBoolLike(item['server_enabled']) ||
          !_isBoolLike(item['plan_enabled']) ||
          !_isBoolLike(item['platform_supported'])) {
        _contractViolation(
          endpoint,
          'protocol[$index] availability flags must be bool-like',
        );
      }
    }
  }

  bool _isTransientNetworkError(Object error) {
    if (error is! DioException) return false;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  Future<T> _withNetworkRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        return await action();
      } catch (error) {
        final shouldRetry =
            attempt < maxAttempts && _isTransientNetworkError(error);
        if (!shouldRetry) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 250 * attempt),
        );
      }
    }
  }

  Map<String, dynamic> _normalizeVpnProfilePayload(
    Map<String, dynamic> payload,
  ) {
    final wrapped = payload['data'];
    if (wrapped is Map) {
      final candidate = Map<String, dynamic>.from(wrapped);
      final looksLikeProfile = candidate.containsKey('device_id') ||
          candidate.containsKey('protocol') ||
          candidate.containsKey('wireguard_config') ||
          candidate.containsKey('profile');
      if (looksLikeProfile) {
        return candidate;
      }
    }
    return payload;
  }

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
      Future<
          ({
            List<ServerRegion> servers,
            Map<String, dynamic> data,
            List<dynamic> rawList,
          })> fetchFrom(String path, String listKey) async {
        final response = await _dio.get<Map<String, dynamic>>(path);
        final data = response.data ?? <String, dynamic>{};
        final rawList =
            data[listKey] is List ? data[listKey] as List : <dynamic>[];
        final servers = rawList
            .whereType<Map>()
            .map((entry) =>
                ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
            .toList();
        return (servers: servers, data: data, rawList: rawList);
      }

      List<ServerRegion> servers;
      String sourcePath;
      try {
        final result = await fetchFrom('/vpn/regions', 'regions');
        // Fall back to /vpn/servers if regions returns an empty list —
        // the backend serves live server data from that endpoint instead.
        if (result.servers.isNotEmpty) {
          servers = result.servers;
          sourcePath = '/vpn/regions';
          if (_strictContractValidation) {
            _validateRegionsContract(result.data, result.rawList);
          }
        } else {
          final fallback = await fetchFrom('/vpn/servers', 'servers');
          servers = fallback.servers;
          sourcePath = '/vpn/servers';
        }
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status != 404 && status != 405) rethrow;
        final result = await fetchFrom('/vpn/servers', 'servers');
        servers = result.servers;
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
      Map<String, dynamic> data;
      try {
        final usageResp =
            await _dio.get<Map<String, dynamic>>('/account/usage');
        final usage = usageResp.data ?? <String, dynamic>{};
        if (_strictContractValidation) {
          _validateUsageContract(usage);
        }
        final quotaBytes = (usage['quota_bytes'] as num?)?.toDouble() ?? 0;
        final usedBytes = (usage['used_bytes'] as num?)?.toDouble() ?? 0;
        final tier = usage['plan_tier']?.toString().toLowerCase() ?? 'free';
        // Pass through ALL backend fields; add computed GB values.
        data = Map<String, dynamic>.from(usage);
        data['data_cap_gb'] =
            quotaBytes > 0 ? quotaBytes / 1024 / 1024 / 1024 : 0;
        data['used_gb'] = usedBytes / 1024 / 1024 / 1024;
        data['plan_name'] ??= tier == 'premium' ? 'Premium' : 'Free';
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status != 404 && status != 405) rethrow;
        final response = await _dio.get<Map<String, dynamic>>('/user/plan');
        data = response.data ?? <String, dynamic>{};
      }
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
          await _withNetworkRetry<Response<Map<String, dynamic>>>(() {
        return _dio.post<Map<String, dynamic>>('/auth/login', data: {
          'email': email,
          'password': password,
        });
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
          await _withNetworkRetry<Response<Map<String, dynamic>>>(() {
        return _dio.post<Map<String, dynamic>>('/auth/register', data: {
          'email': email,
          'password': password,
          'password_confirm': password,
        });
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
    final requestedProtocol = protocol == VpnProtocol.auto
        ? 'auto'
        : vpnProtocolStorageValue(protocol);
    final requestedServer = (serverId ?? '').trim();
    AppLogger.info(
      'VPN profile request: protocol=$requestedProtocol '
      'server=${requestedServer.isEmpty ? "-" : requestedServer} '
      'deviceId=${deviceId ?? "-"} '
      'deviceType=${deviceType.trim().isEmpty ? "unknown" : deviceType.trim()} '
      'baseUrl=${_config.apiBaseUrl}',
    );
    final requestPayload = <String, dynamic>{
      if (deviceId != null && deviceId > 0) 'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
      if (protocol != VpnProtocol.auto)
        'protocol': vpnProtocolStorageValue(protocol),
      if (serverId != null && serverId.isNotEmpty) 'server_id': serverId,
      if (forceRotateKeys) 'force_rotate_keys': true,
    };
    try {
      final response =
          await _withNetworkRetry<Response<Map<String, dynamic>>>(() {
        return _dio.post<Map<String, dynamic>>(
          '/vpn/profile',
          data: requestPayload,
          cancelToken: cancelToken,
        );
      });
      final data =
          _normalizeVpnProfilePayload(response.data ?? <String, dynamic>{});
      final responseProtocol = data['protocol']?.toString().trim();
      final responseServer = data['server_id']?.toString().trim();
      final requestId =
          _responseHeader(response.headers, 'x-request-id') ?? '-';
      AppLogger.info(
        'VPN profile response: status=${response.statusCode ?? 200} '
        'requestId=$requestId '
        'protocol=${responseProtocol?.isNotEmpty == true ? responseProtocol : requestedProtocol} '
        'server=${responseServer?.isNotEmpty == true ? responseServer : "-"}',
      );
      return VpnProfile.fromJson(data);
    } on DioException catch (error, stackTrace) {
      final status = error.response?.statusCode;
      final requestId =
          _responseHeader(error.response?.headers, 'x-request-id') ?? '-';
      final apiCode = _extractApiErrorCode(error.response?.data) ?? '-';
      final apiMessage = _extractApiErrorMessage(error.response?.data);
      AppLogger.warning(
        'VPN profile request failed: status=${status ?? -1} '
        'requestId=$requestId code=$apiCode '
        'protocol=$requestedProtocol '
        'server=${requestedServer.isEmpty ? "-" : requestedServer} '
        'deviceId=${deviceId ?? "-"} '
        'dioType=${error.type.name}'
        '${apiMessage != null ? ' message=$apiMessage' : ''}',
      );
      AppLogger.error('VPN profile fetch failed',
          error: error, stackTrace: stackTrace);
      rethrow;
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
      if (_strictContractValidation) {
        _validateProtocolsContract(data);
      }
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

  Future<VpnResolvedRegion> resolveRegion({
    required VpnProtocol protocol,
    required String deviceType,
    String? preferredRegion,
    CancelToken? cancelToken,
  }) async {
    final protocolValue = protocol == VpnProtocol.auto
        ? vpnProtocolStorageValue(VpnProtocol.wireGuard)
        : vpnProtocolStorageValue(protocol);
    final response = await _dio.get<Map<String, dynamic>>(
      '/vpn/resolve-region',
      queryParameters: <String, dynamic>{
        'protocol': protocolValue,
        if (deviceType.trim().isNotEmpty && deviceType != 'unknown')
          'device_type': deviceType,
        if (preferredRegion != null && preferredRegion.trim().isNotEmpty)
          'preferred_region': preferredRegion.trim(),
      },
      cancelToken: cancelToken,
    );
    final data = response.data ?? const <String, dynamic>{};
    return VpnResolvedRegion.fromJson(data);
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

  // ── Profile management ───────────────────────────────────────────────

  /// Fetch current user profile from /auth/me.
  Future<Map<String, dynamic>> fetchProfile() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      return response.data ?? <String, dynamic>{};
    } catch (error, stackTrace) {
      AppLogger.error('Fetch profile error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update email via POST /auth/update-email.
  Future<Map<String, dynamic>> updateEmail({
    required String newEmail,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/update-email',
        data: {'new_email': newEmail, 'password': password},
      );
      return response.data ?? <String, dynamic>{};
    } catch (error, stackTrace) {
      AppLogger.error('Update email error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update password via POST /auth/update-password.
  Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/update-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
      return response.data ?? <String, dynamic>{};
    } catch (error, stackTrace) {
      AppLogger.error('Update password error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ── Device management ────────────────────────────────────────────────

  /// List registered devices for the current user.
  Future<DeviceListResult> listDevices() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/vpn/devices');
      final data = response.data ?? <String, dynamic>{};
      final rawDevices = (data['devices'] as List?) ?? [];
      final devices = rawDevices
          .whereType<Map>()
          .map((d) => DeviceInfo.fromJson(Map<String, dynamic>.from(d)))
          .toList();
      return DeviceListResult(
        devices: devices,
        total: (data['total'] as int?) ?? devices.length,
        limit: (data['limit'] as int?) ?? 1,
        remaining: (data['remaining'] as int?) ?? 0,
      );
    } catch (error, stackTrace) {
      AppLogger.error('List devices error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Revoke (delete) a device by its ID.
  Future<void> deleteDevice(int deviceId) async {
    try {
      await _dio.delete<void>('/vpn/devices/$deviceId');
    } catch (error, stackTrace) {
      AppLogger.error('Delete device error',
          error: error, stackTrace: stackTrace);
      rethrow;
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

class VpnResolvedRegion {
  const VpnResolvedRegion({
    required this.selectedRegionId,
    required this.reason,
    this.protocol,
    this.deviceType,
    this.preferredRegion,
    this.userGeoGroup,
    this.userCountryCode,
    this.selectedRegionGroup,
    this.cacheHit = false,
  });

  final String selectedRegionId;
  final String reason;
  final String? protocol;
  final String? deviceType;
  final String? preferredRegion;
  final String? userGeoGroup;
  final String? userCountryCode;
  final String? selectedRegionGroup;
  final bool cacheHit;

  factory VpnResolvedRegion.fromJson(Map<String, dynamic> json) {
    bool b(String key) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value?.toString().toLowerCase() == 'true';
    }

    String? s(String key) {
      final raw = json[key]?.toString();
      if (raw == null) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return VpnResolvedRegion(
      selectedRegionId: s('selected_region_id') ?? '',
      reason: s('reason') ?? '',
      protocol: s('protocol'),
      deviceType: s('device_type'),
      preferredRegion: s('preferred_region'),
      userGeoGroup: s('user_geo_group'),
      userCountryCode: s('user_country_code'),
      selectedRegionGroup: s('selected_region_group'),
      cacheHit: b('cache_hit'),
    );
  }
}

// ── Device models ─────────────────────────────────────────────────────

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    this.name,
    this.deviceType,
    required this.ipAddress,
    this.serverLocation,
    required this.isActive,
    required this.createdAt,
    this.lastHandshake,
    this.dataSentMb = 0,
    this.dataReceivedMb = 0,
  });

  final int id;
  final String? name;
  final String? deviceType;
  final String ipAddress;
  final String? serverLocation;
  final bool isActive;
  final String createdAt;
  final String? lastHandshake;
  final double dataSentMb;
  final double dataReceivedMb;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString(),
      deviceType: json['device_type']?.toString(),
      ipAddress: json['ip_address']?.toString() ?? '',
      serverLocation: json['server_location']?.toString(),
      isActive: json['is_active'] == true,
      createdAt: json['created_at']?.toString() ?? '',
      lastHandshake: json['last_handshake']?.toString(),
      dataSentMb: (json['data_sent_mb'] as num?)?.toDouble() ?? 0,
      dataReceivedMb: (json['data_received_mb'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DeviceListResult {
  const DeviceListResult({
    required this.devices,
    required this.total,
    required this.limit,
    required this.remaining,
  });

  final List<DeviceInfo> devices;
  final int total;
  final int limit;
  final int remaining;
}
