import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_account.dart';
import '../core/models/user_plan.dart';
import '../core/services/auth_session.dart';
import '../core/models/vpn_profile.dart';
import '../core/models/vpn_protocol.dart';
import '../core/models/protocol_availability.dart';

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
          ),
        );
    // Handle all HTTP responses in the interceptor below. This guarantees an
    // expired token cannot leave the shell authenticated just because Dio
    // converted the 401 into an error before application code sees it.
    _dio.options.validateStatus = (_) => true;
    if (session != null) {
      // Insert first so failures raised by later transport/interceptor layers
      // still return through this error handler.
      _dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final token = session.accessToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            return handler.next(options);
          },
          onResponse: (response, handler) async {
            final status = response.statusCode ?? 0;
            if (status == 401) {
              await _expireSession(session);
            }
            if (status >= 400) {
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  type: DioExceptionType.badResponse,
                ),
              );
            }
            return handler.next(response);
          },
          onError: (error, handler) async {
            // A restored token only proves that secure storage was readable;
            // it does not prove that the token is still valid. Without this
            // recovery path the app keeps rendering the authenticated shell
            // while every backend-backed provider fails with 401.
            if (error.response?.statusCode == 401) {
              await _expireSession(session);
            }
            return handler.next(error);
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
  Future<void>? _sessionExpiryInFlight;

  static const Duration _serversCacheTtl = Duration(minutes: 5);
  static const Duration _planCacheTtl = Duration(minutes: 2);

  Future<void> _expireSession(AuthSession session) {
    return _sessionExpiryInFlight ??= session.clearSession().whenComplete(() {
      _sessionExpiryInFlight = null;
    });
  }

  Future<List<ServerRegion>> fetchServers({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedServers != null && _serversFetchedAt != null) {
      final age = DateTime.now().difference(_serversFetchedAt!);
      if (age < _serversCacheTtl) {
        return _cachedServers!;
      }
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>('/vpn/servers');
      final data = response.data ?? <String, dynamic>{};
      final rawList =
          data['servers'] is List ? data['servers'] as List : <dynamic>[];
      final servers = rawList
          .whereType<Map>()
          .map((entry) =>
              ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
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

  Future<UserAccount> fetchCurrentUser() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      final data = response.data ?? <String, dynamic>{};
      return UserAccount.fromJson(data);
    } catch (error, stackTrace) {
      AppLogger.error('Current user lookup failed',
          error: error, stackTrace: stackTrace);
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
      final accessToken = data['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) {
        if (data['requires_2fa'] == true) {
          throw StateError(
              'Two-factor authentication is required for this account.');
        }
        throw StateError('Login response did not include an access token.');
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
      final accessToken = data['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }
      return AuthTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token']?.toString(),
      );
    } catch (error, stackTrace) {
      AppLogger.error('Registration error',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<VpnProtocol, ProtocolAvailability>> fetchProtocolAvailability({
    String? deviceType,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/vpn/protocols',
        queryParameters: {
          if (deviceType != null && deviceType.isNotEmpty)
            'device_type': deviceType,
        },
      );
      final rawProtocols = response.data?['protocols'];
      if (rawProtocols is! List) {
        throw StateError('Protocol availability response was malformed.');
      }
      final availability = <VpnProtocol, ProtocolAvailability>{};
      for (final entry in rawProtocols.whereType<Map>()) {
        final payload = Map<String, dynamic>.from(entry);
        if (payload['protocol']?.toString().toLowerCase() != 'wireguard') {
          continue;
        }
        final item = ProtocolAvailability.fromJson(payload);
        availability[item.protocol] = item;
      }
      availability.putIfAbsent(
        VpnProtocol.wireGuard,
        () => const ProtocolAvailability(
          protocol: VpnProtocol.wireGuard,
          enabled: false,
          serverEnabled: false,
          platformSupported: false,
          reason: 'WireGuard availability was not returned by the backend.',
        ),
      );
      return availability;
    } catch (error, stackTrace) {
      AppLogger.error('Protocol availability lookup failed',
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
  }) async {
    try {
      final profileServerLabel =
          serverId == null || serverId.isEmpty ? 'auto-select' : serverId;
      final profileDeviceIdLabel =
          deviceId != null && deviceId > 0 ? 'present' : 'none';
      AppLogger.info(
        'VPN profile request: protocol=${vpnProtocolStorageValue(protocol)} '
        'device_type=$deviceType '
        'server=$profileServerLabel '
        'device_id=$profileDeviceIdLabel '
        'api_base=${_config.apiBaseUrl}',
      );
      final response = await _dio.post<Map<String, dynamic>>(
        '/vpn/profile',
        data: {
          if (deviceId != null && deviceId > 0) 'device_id': deviceId,
          'device_name': deviceName,
          'device_type': deviceType,
          'protocol': vpnProtocolStorageValue(protocol),
          if (serverId != null && serverId.isNotEmpty) 'server_id': serverId,
          if (forceRotateKeys) 'force_rotate_keys': true,
        },
      );
      final data = response.data ?? <String, dynamic>{};
      return VpnProfile.fromJson(data);
    } catch (error, stackTrace) {
      AppLogger.error('VPN profile fetch failed',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Find the single active device that can safely be reused after an app
  /// reinstall. Device names are regenerated locally, so matching by name
  /// alone can incorrectly hit the account's device limit.
  Future<int?> findReusableDeviceId({required String deviceType}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/vpn/devices');
      final rawDevices = response.data?['devices'];
      if (rawDevices is! List) return null;
      final active = rawDevices
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final type = item['device_type']?.toString().toLowerCase();
            return item['is_active'] == true &&
                item['is_revoked'] != true &&
                (type == null || type == deviceType.toLowerCase());
          })
          .map((item) => int.tryParse(item['id']?.toString() ?? ''))
          .whereType<int>()
          .toList();
      return active.length == 1 ? active.single : null;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Reusable VPN device lookup failed.',
      );
      AppLogger.error(
        'Reusable VPN device lookup error',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Notify the backend that the VPN tunnel has been established.
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/vpn/connect',
        data: {
          if (serverId != null && serverId.isNotEmpty) ...{
            'server_id': serverId,
            'region': serverId,
          },
          if (protocol != null) 'protocol': vpnProtocolStorageValue(protocol),
        },
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

  Future<void> logout() async {
    try {
      await _dio.post<Map<String, dynamic>>('/auth/logout');
    } catch (error, stackTrace) {
      AppLogger.warning(
          'Backend logout failed; local session will still clear.');
      AppLogger.error('Logout error', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<int?> startUsageSession({
    required int deviceId,
    required String serverId,
    required VpnProtocol protocol,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/vpn/usage/sessions/start',
      data: {
        'device_id': deviceId,
        'server_id': serverId,
        'protocol': vpnProtocolStorageValue(protocol),
        'idempotency_key': idempotencyKey,
      },
    );
    final sessionId = response.data?['session_id'];
    return sessionId is num ? sessionId.toInt() : int.tryParse('$sessionId');
  }

  Future<void> reportUsage({
    required int sessionId,
    required int sequence,
    required int bytesSent,
    required int bytesReceived,
    required String idempotencyKey,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/vpn/usage/sessions/$sessionId/increment',
      data: {
        'sequence': sequence,
        'bytes_sent': bytesSent,
        'bytes_received': bytesReceived,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  Future<void> finalizeUsageSession({
    required int sessionId,
    required String idempotencyKey,
    String reason = 'client_disconnect',
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/vpn/usage/sessions/$sessionId/disconnect',
      data: {'idempotency_key': idempotencyKey, 'reason': reason},
    );
  }
}

class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}
