import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_plan.dart';
import '../core/services/auth_session.dart';
import '../core/services/secure_storage.dart';
import '../core/models/vpn_profile.dart';
import '../core/models/vpn_protocol.dart';
import '../core/models/vpn_protocol_catalog.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  // ApiClient reads auth tokens dynamically from the AuthSession instance.
  // Recreating Dio on every auth notify causes avoidable churn and can close
  // adapters while requests are still in flight.
  final session = ref.read(authSessionProvider);
  final client = ApiClient(config, session: session);
  ref.onDispose(client.dispose);
  return client;
});

class ControlPlaneSessionEvent {
  const ControlPlaneSessionEvent({
    required this.reason,
    required this.generation,
    required this.at,
  });

  final String reason;
  final int generation;
  final DateTime at;
}

typedef ControlPlaneReconnectHook = FutureOr<void> Function(
  ControlPlaneSessionEvent event,
);

class ApiClient {
  ApiClient(
    this._config, {
    AuthSession? session,
    Dio? dio,
    SecureStorage? storage,
  })  : _storage = storage ?? SecureStorage(),
        _session = session {
    _effectiveApiBaseUrl = _config.httpsPreferred &&
            _config.apiBaseUrl.toLowerCase().startsWith('http://')
        ? _config.apiBaseUrl
            .replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://')
        : _config.apiBaseUrl;
    _dio = dio ?? _createDio(session: _session);

    AppLogger.info('ApiClient: initialized with baseUrl=$_effectiveApiBaseUrl');
    _debugLog('api_client_init', <String, Object?>{
      'base_url': _effectiveApiBaseUrl,
      'portal_url': _config.portalUrl,
      'upgrade_url': _config.upgradeUrl,
      'https_preferred': _config.httpsPreferred,
    });
  }

  final AppConfig _config;
  final SecureStorage _storage;
  final AuthSession? _session;
  late final String _effectiveApiBaseUrl;
  late Dio _dio;
  List<ServerRegion>? _cachedServers;
  DateTime? _serversFetchedAt;
  UserPlan? _cachedPlan;
  DateTime? _planFetchedAt;
  Future<List<ServerRegion>>? _serversInFlight;
  Future<UserPlan>? _planInFlight;
  Future<Map<String, dynamic>>? _profileInFlight;
  Future<DeviceListResult>? _deviceListInFlight;
  final Map<String, Future<VpnProtocolCatalog>> _protocolCatalogInFlight =
      <String, Future<VpnProtocolCatalog>>{};
  final Map<Object, ControlPlaneReconnectHook> _reconnectHooks =
      <Object, ControlPlaneReconnectHook>{};
  Future<void> _reinitializeQueue = Future<void>.value();
  int _networkSessionGeneration = 0;

  static const Duration _serversCacheTtl = Duration(minutes: 5);
  static const Duration _planCacheTtl = Duration(minutes: 2);
  static const bool _strictContractValidation = !kReleaseMode;
  static const Duration _networkRetryBaseDelay = Duration(milliseconds: 350);

  int get networkSessionGeneration => _networkSessionGeneration;

  void registerControlPlaneReconnectHook(
    Object owner,
    ControlPlaneReconnectHook hook,
  ) {
    _reconnectHooks[owner] = hook;
  }

  void unregisterControlPlaneReconnectHook(Object owner) {
    _reconnectHooks.remove(owner);
  }

  Future<void> reinitializeControlPlane({
    required String reason,
  }) {
    _reinitializeQueue = _reinitializeQueue
        .catchError((Object _, StackTrace __) {})
        .then((_) async {
      final previous = _dio;
      _dio = _createDio(session: _session);
      _networkSessionGeneration += 1;
      previous.close(force: true);

      final event = ControlPlaneSessionEvent(
        reason: reason,
        generation: _networkSessionGeneration,
        at: DateTime.now().toUtc(),
      );
      for (final hook in List<ControlPlaneReconnectHook>.from(
        _reconnectHooks.values,
      )) {
        try {
          await hook(event);
        } catch (error, stackTrace) {
          AppLogger.error(
            'Control-plane reconnect hook failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _debugLog('control_plane_reinitialized', <String, Object?>{
        'reason': reason,
        'generation': _networkSessionGeneration,
      });
    });
    return _reinitializeQueue;
  }

  void dispose() {
    _reconnectHooks.clear();
    _protocolCatalogInFlight.clear();
    _dio.close(force: true);
  }

  Dio _createDio({AuthSession? session}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: _effectiveApiBaseUrl,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    _configureDebugHttpClient(dio);
    if (session != null) {
      _attachSessionInterceptors(dio, session);
    }
    return dio;
  }

  void _configureDebugHttpClient(Dio dio) {
    // In non-release builds, allow self-signed certificates so the dev VPS
    // (which uses a self-signed cert on an IP address) remains reachable.
    // This path is never compiled into release builds.
    if (!kReleaseMode && dio.httpClientAdapter is IOHttpClientAdapter) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
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
  }

  void _attachSessionInterceptors(Dio dio, AuthSession session) {
    dio.interceptors.add(
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
              _debugAuthRefresh(
                '[AUTH_REFRESH] no refresh token — clearing session',
              );
              await session.clearSession();
              return handler.next(error);
            }
            _debugAuthRefresh(
              '[AUTH_REFRESH] 401 received — attempting token refresh',
            );
            final refreshDio = _buildRefreshDio();
            final refreshResp = await refreshDio.post<Map<String, dynamic>>(
              '/auth/refresh',
              data: {'refresh_token': refreshToken},
            );
            final newAccess = refreshResp.data?['access_token']?.toString();
            final newRefresh = refreshResp.data?['refresh_token']?.toString();
            if (newAccess == null || newAccess.isEmpty) {
              _debugAuthRefresh(
                '[AUTH_REFRESH] refresh response missing access_token',
              );
              await session.clearSession();
              return handler.next(error);
            }
            await session.setSession(
              accessToken: newAccess,
              refreshToken: newRefresh,
            );
            _debugAuthRefresh(
              '[AUTH_REFRESH] tokens refreshed — retrying request',
            );
            // Retry the original request with the new token.
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newAccess';
            opts.extra['_isRetry'] = true;
            final retryResp = await _dio.fetch(opts);
            return handler.resolve(retryResp);
          } catch (refreshError) {
            _debugAuthRefresh(
              '[AUTH_REFRESH] refresh failed: $refreshError — clearing session',
            );
            await session.clearSession();
            return handler.next(error);
          }
        },
      ),
    );
  }

  Dio _buildRefreshDio() {
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: _effectiveApiBaseUrl,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    if (!kReleaseMode && refreshDio.httpClientAdapter is IOHttpClientAdapter) {
      (refreshDio.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
          () {
        final client = HttpClient();
        client.badCertificateCallback = (_, __, ___) => true;
        return client;
      };
    }
    return refreshDio;
  }

  void _debugAuthRefresh(String message) {
    AppLogger.debug(message, tag: 'SecureWave.Auth');
  }

  void _debugLog(String event, Map<String, Object?> payload) {
    if (!kDebugMode) return;
    final data = <String, Object?>{
      'event': event,
      ..._sanitizeDebugPayload(payload),
    };
    AppLogger.debug('[SW_API] ${jsonEncode(data)}', tag: 'SecureWave.API');
  }

  Map<String, Object?> _sanitizeDebugPayload(Map<String, Object?> payload) {
    final sanitized = <String, Object?>{};
    for (final entry in payload.entries) {
      sanitized[entry.key] = _sanitizeDebugValue(entry.key, entry.value);
    }
    return sanitized;
  }

  Object? _sanitizeDebugValue(String key, Object? value) {
    final normalized = key.trim().toLowerCase();
    if (normalized == 'email' || normalized.endsWith('_email')) {
      return '[REDACTED_EMAIL]';
    }
    if (normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized.contains('cookie') ||
        normalized.contains('private_key')) {
      return '[REDACTED]';
    }
    if (value is Map<String, Object?>) {
      return _sanitizeDebugPayload(value);
    }
    return value;
  }

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
    Duration baseDelay = _networkRetryBaseDelay,
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
        final factor = 1 << (attempt - 1);
        final delay = Duration(milliseconds: baseDelay.inMilliseconds * factor);
        await Future<void>.delayed(delay);
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

  Future<void> _persistServerCache({
    required List<dynamic> rawList,
    required String source,
  }) async {
    try {
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'source': source,
        'servers': rawList,
      };
      await _storage.saveString(
        SecureStorage.serversCatalogCacheKey,
        jsonEncode(payload),
      );
    } catch (_) {
      // Cache persistence is best-effort only.
    }
  }

  Future<List<ServerRegion>> _loadCachedServers() async {
    try {
      final raw =
          await _storage.getString(SecureStorage.serversCatalogCacheKey);
      if (raw == null || raw.trim().isEmpty) return const <ServerRegion>[];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <ServerRegion>[];
      final map = Map<String, dynamic>.from(decoded);
      final list = map['servers'];
      if (list is! List) return const <ServerRegion>[];
      final parsed = <ServerRegion>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          parsed.add(ServerRegion.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Tolerate malformed cached entries.
        }
      }
      return parsed;
    } catch (_) {
      return const <ServerRegion>[];
    }
  }

  Future<Map<String, dynamic>> fetchHealth({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/health',
        cancelToken: cancelToken,
      );
      final payload = response.data ?? const <String, dynamic>{};
      _debugLog('health_ok', <String, Object?>{
        'base_url': _effectiveApiBaseUrl,
        'status': response.statusCode ?? 200,
        'keys': payload.keys.toList(),
      });
      return payload;
    } catch (error, stackTrace) {
      _debugLog('health_fail', <String, Object?>{
        'base_url': _effectiveApiBaseUrl,
        'error': error.toString(),
      });
      AppLogger.error(
        'Health check error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<ServerRegion>> fetchServers({bool forceRefresh = false}) async {
    if (!forceRefresh && _serversInFlight != null) {
      return _serversInFlight!;
    }
    final future = _fetchServersInternal(forceRefresh: forceRefresh);
    _serversInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_serversInFlight, future)) {
        _serversInFlight = null;
      }
    }
  }

  Future<List<ServerRegion>> _fetchServersInternal({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && _cachedServers != null && _serversFetchedAt != null) {
      final age = DateTime.now().difference(_serversFetchedAt!);
      if (age < _serversCacheTtl) {
        AppLogger.vpn(
          'API',
          'SERVER_LIST_LOADED',
          fields: <String, Object?>{
            'count': _cachedServers!.length,
            'source': 'cache',
          },
        );
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
        final response =
            await _withNetworkRetry<Response<Map<String, dynamic>>>(() {
          return _dio.get<Map<String, dynamic>>(path);
        }, maxAttempts: 3);
        final data = response.data ?? <String, dynamic>{};
        final rawList =
            data[listKey] is List ? data[listKey] as List : <dynamic>[];
        final servers = <ServerRegion>[];
        for (final entry in rawList) {
          if (entry is! Map) continue;
          try {
            servers
                .add(ServerRegion.fromJson(Map<String, dynamic>.from(entry)));
          } catch (error) {
            _debugLog('servers_parse_skip', <String, Object?>{
              'path': path,
              'error': error.toString(),
            });
          }
        }
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
        'VPN servers fetched: count=${servers.length} source=$sourcePath baseUrl=$_effectiveApiBaseUrl sample=${servers.take(5).map((s) => s.name).join(", ")}',
      );
      AppLogger.vpn(
        'API',
        'SERVER_LIST_LOADED',
        fields: <String, Object?>{
          'count': servers.length,
          'source': sourcePath,
        },
      );
      _debugLog('servers_ok', <String, Object?>{
        'count': servers.length,
        'source': sourcePath,
        'base_url': _effectiveApiBaseUrl,
      });
      if (servers.isNotEmpty) {
        final rawPayload = sourcePath == '/vpn/regions'
            ? servers
                .map((region) => <String, dynamic>{
                      'server_id': region.id,
                      'name': region.name,
                      'city': region.city,
                      'country': region.country,
                      'country_code': region.countryCode,
                      'region': region.region,
                      'region_group': region.regionGroup,
                      'latency_ms': region.latencyMs,
                      'latency_priority': region.latencyPriority,
                      'health_status': region.healthStatus,
                      'region_health_status': region.regionHealthStatus,
                      'region_health_last_checked_at':
                          region.regionHealthLastCheckedAt,
                      'region_health_reason_code':
                          region.regionHealthReasonCode,
                      'public_ip': region.publicIp,
                      'tier_restriction': region.tierRestriction,
                      'premium_only': region.premiumOnly,
                      'supported_protocols': region.supportedProtocols,
                    })
                .toList(growable: false)
            : servers
                .map((region) => <String, dynamic>{
                      'server_id': region.id,
                      'name': region.name,
                      'city': region.city,
                      'country': region.country,
                      'country_code': region.countryCode,
                      'region': region.region,
                      'region_group': region.regionGroup,
                      'latency_ms': region.latencyMs,
                      'latency_priority': region.latencyPriority,
                      'health_status': region.healthStatus,
                      'region_health_status': region.regionHealthStatus,
                      'region_health_last_checked_at':
                          region.regionHealthLastCheckedAt,
                      'region_health_reason_code':
                          region.regionHealthReasonCode,
                      'public_ip': region.publicIp,
                      'tier_restriction': region.tierRestriction,
                      'premium_only': region.premiumOnly,
                      'supported_protocols': region.supportedProtocols,
                    })
                .toList(growable: false);
        unawaited(
          _persistServerCache(rawList: rawPayload, source: sourcePath),
        );
      }
      _cachedServers = servers;
      _serversFetchedAt = DateTime.now();
      return servers;
    } catch (error, stackTrace) {
      _debugLog('servers_fail', <String, Object?>{
        'error': error.toString(),
      });
      final cached = await _loadCachedServers();
      if (cached.isNotEmpty) {
        _debugLog('servers_cache_fallback', <String, Object?>{
          'count': cached.length,
        });
        _cachedServers = cached;
        _serversFetchedAt = DateTime.now();
        return cached;
      }
      AppLogger.error('Server list error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<UserPlan> fetchUserPlan({bool forceRefresh = false}) async {
    if (!forceRefresh && _planInFlight != null) {
      return _planInFlight!;
    }
    final future = _fetchUserPlanInternal(forceRefresh: forceRefresh);
    _planInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_planInFlight, future)) {
        _planInFlight = null;
      }
    }
  }

  Future<UserPlan> _fetchUserPlanInternal({required bool forceRefresh}) async {
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
    _debugLog('auth_login_start', <String, Object?>{
      'base_url': _effectiveApiBaseUrl,
      'email': email,
    });
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
      _debugLog('auth_login_ok', <String, Object?>{
        'status': response.statusCode ?? 200,
        'has_refresh': (data['refresh_token']?.toString() ?? '').isNotEmpty,
      });
      return AuthTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      _debugLog('auth_login_fail', <String, Object?>{
        'error': error.toString(),
      });
      AppLogger.error('Login error', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<AuthTokens?> register(
      {required String email, required String password}) async {
    _debugLog('auth_register_start', <String, Object?>{
      'base_url': _effectiveApiBaseUrl,
      'email': email,
    });
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
      _debugLog('auth_register_ok', <String, Object?>{
        'status': response.statusCode ?? 200,
        'issued_tokens': true,
      });
      return AuthTokens(
        accessToken: data['access_token']?.toString() ?? '',
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      _debugLog('auth_register_fail', <String, Object?>{
        'error': error.toString(),
      });
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
      'baseUrl=$_effectiveApiBaseUrl',
    );
    _debugLog('profile_start', <String, Object?>{
      'protocol': requestedProtocol,
      'server_id': requestedServer,
      'device_id': deviceId,
      'device_type': deviceType,
    });
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
      AppLogger.vpn(
        'API',
        'PROFILE_GENERATED',
        fields: <String, Object?>{
          'status': response.statusCode ?? 200,
          'request_id': requestId,
          'protocol': responseProtocol ?? requestedProtocol,
          'server_id': responseServer ?? '-',
        },
      );
      _debugLog('profile_ok', <String, Object?>{
        'status': response.statusCode ?? 200,
        'protocol': responseProtocol ?? requestedProtocol,
        'server_id': responseServer ?? '',
        'request_id': requestId,
      });
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
      _debugLog('profile_fail', <String, Object?>{
        'status': status,
        'code': apiCode,
        'message': apiMessage,
        'request_id': requestId,
      });
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
    final requestKey = deviceType.trim().toLowerCase();
    if (cancelToken == null) {
      final existing = _protocolCatalogInFlight[requestKey];
      if (existing != null) {
        return existing;
      }
      final future = _fetchVpnProtocolsInternal(
        deviceType: deviceType,
        cancelToken: cancelToken,
      );
      _protocolCatalogInFlight[requestKey] = future;
      try {
        return await future;
      } finally {
        if (identical(_protocolCatalogInFlight[requestKey], future)) {
          _protocolCatalogInFlight.remove(requestKey);
        }
      }
    }
    return _fetchVpnProtocolsInternal(
      deviceType: deviceType,
      cancelToken: cancelToken,
    );
  }

  Future<VpnProtocolCatalog> _fetchVpnProtocolsInternal({
    required String deviceType,
    CancelToken? cancelToken,
  }) async {
    try {
      _debugLog('protocols_start', <String, Object?>{
        'device_type': deviceType,
        'base_url': _effectiveApiBaseUrl,
      });
      final response =
          await _withNetworkRetry<Response<Map<String, dynamic>>>(() {
        return _dio.get<Map<String, dynamic>>(
          '/vpn/protocols',
          queryParameters: {
            if (deviceType.isNotEmpty && deviceType != 'unknown')
              'device_type': deviceType,
          },
          cancelToken: cancelToken,
        );
      });
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
        'VPN protocols fetched: deviceType=$deviceType enabled=${enabled.join(",")} baseUrl=$_effectiveApiBaseUrl',
      );
      _debugLog('protocols_ok', <String, Object?>{
        'device_type': deviceType,
        'enabled': enabled,
        'count': catalog.protocols.length,
      });
      return catalog;
    } catch (error, stackTrace) {
      _debugLog('protocols_fail', <String, Object?>{
        'device_type': deviceType,
        'error': error.toString(),
      });
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
    if (_profileInFlight != null) {
      return _profileInFlight!;
    }
    final future = _fetchProfileInternal();
    _profileInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_profileInFlight, future)) {
        _profileInFlight = null;
      }
    }
  }

  Future<Map<String, dynamic>> _fetchProfileInternal() async {
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
    if (_deviceListInFlight != null) {
      return _deviceListInFlight!;
    }
    final future = _listDevicesInternal();
    _deviceListInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_deviceListInFlight, future)) {
        _deviceListInFlight = null;
      }
    }
  }

  Future<DeviceListResult> _listDevicesInternal() async {
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
