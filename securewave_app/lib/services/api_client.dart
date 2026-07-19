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

  Future<List<ServerRegion>> fetchServers({
    bool forceRefresh = false,
    String? deviceType,
  }) async {
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
      final response = await _dio.get<Map<String, dynamic>>(
        '/vpn/servers',
        queryParameters: {
          if (deviceType != null && deviceType.isNotEmpty)
            'device_type': deviceType,
        },
      );
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
      if (_config.useMockApi) {
        _logMockApi();
        AppLogger.warning(
            'Server list unavailable; using mock regions (mock API mode).');
        AppLogger.error('Server list error',
            error: error, stackTrace: stackTrace);
        final data = _mockServers();
        _cachedServers = data;
        _serversFetchedAt = DateTime.now();
        return data;
      }
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
      if (_config.useMockApi) {
        _logMockApi();
        AppLogger.warning(
            'Plan lookup failed; using mock plan (mock API mode).');
        AppLogger.error('Plan error', error: error, stackTrace: stackTrace);
        final plan = _mockPlan();
        _cachedPlan = plan;
        _planFetchedAt = DateTime.now();
        return plan;
      }
      AppLogger.error('Plan error', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<UserAccount> fetchCurrentUser() async {
    if (_config.useMockApi) {
      _logMockApi();
      return const UserAccount(
        id: 0,
        email: 'demo@securewave.local',
        isActive: true,
        emailVerified: true,
        has2fa: false,
        subscriptionStatus: 'basic',
      );
    }
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
    if (_config.useMockApi) {
      _logMockApi();
      return _mockTokens(email);
    }
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
    if (_config.useMockApi) {
      _logMockApi();
      return _mockTokens(email);
    }
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
    if (_config.useMockApi) {
      _logMockApi();
      return {
        VpnProtocol.wireGuard: const ProtocolAvailability(
          protocol: VpnProtocol.wireGuard,
          enabled: true,
          serverEnabled: true,
          platformSupported: true,
        ),
        VpnProtocol.openVpn: const ProtocolAvailability(
          protocol: VpnProtocol.openVpn,
          enabled: false,
          serverEnabled: false,
          platformSupported: true,
          reason: 'OpenVPN runtime evidence is not configured in mock mode.',
        ),
        VpnProtocol.ikev2: const ProtocolAvailability(
          protocol: VpnProtocol.ikev2,
          enabled: false,
          serverEnabled: false,
          platformSupported: false,
          reason: 'IKEv2 is not release-ready for Linux.',
        ),
      };
    }
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
        final item = ProtocolAvailability.fromJson(
          Map<String, dynamic>.from(entry),
        );
        availability[item.protocol] = item;
      }
      return availability;
    } catch (error, stackTrace) {
      AppLogger.error('Protocol availability lookup failed',
          error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  AuthTokens _mockTokens(String email) {
    final handle = email.split('@').first;
    return AuthTokens(
        accessToken: 'mock-token-$handle',
        refreshToken: 'mock-refresh-$handle');
  }

  List<ServerRegion> _mockServers() {
    return const [
      ServerRegion(
          id: 'us-chi',
          name: 'Chicago, IL',
          country: 'United States',
          latencyMs: 28),
      ServerRegion(
          id: 'us-nyc',
          name: 'New York, NY',
          country: 'United States',
          latencyMs: 42),
      ServerRegion(
          id: 'uk-lon',
          name: 'London',
          country: 'United Kingdom',
          latencyMs: 75),
      ServerRegion(
          id: 'de-fra', name: 'Frankfurt', country: 'Germany', latencyMs: 58),
      ServerRegion(
          id: 'sg-sin', name: 'Singapore', country: 'Singapore', latencyMs: 91),
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

  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
  }) async {
    if (_config.useMockApi) {
      _logMockApi();
      return VpnProfile.fromJson({
        'device_id': 0,
        'device_name': deviceName,
        'device_type': deviceType,
        'protocol': 'wireguard',
        'server_id': serverId ?? 'mock',
        'server_location': 'Mock',
        'issued_at': DateTime.now().toIso8601String(),
        'expires_at':
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'wireguard_config': _mockVpnConfig(),
        'openvpn_config': '',
        'ikev2_config': '',
        'dns': {
          'servers': ['94.140.14.14', '94.140.15.15'],
          'ad_malware_blocking': 'on',
          'enforcement': 'config',
        },
        'kill_switch': {
          'mode': 'enabled',
          'enforcement': 'best effort',
        },
        'peer_registered': true,
        'registration_status': 'mock',
      });
    }
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

  /// Capture a non-identifying pre-connect source observation.
  ///
  /// The backend returns an HMAC fingerprint, never the observed public IP.
  /// It is consumed once by [verifyVpnEgress] after the OpenVPN helper has
  /// established the tunnel.
  Future<String> captureVpnEgressBaseline() async {
    if (_config.useMockApi) {
      throw StateError('Mock API cannot certify a VPN egress path.');
    }
    final response =
        await _dio.post<Map<String, dynamic>>('/vpn/egress/baseline');
    final fingerprint = response.data?['fingerprint']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw StateError('VPN egress baseline response was malformed.');
    }
    return fingerprint;
  }

  /// Verify that OpenVPN moved HTTPS egress to its selected server.
  ///
  /// This is intentionally an authenticated control-plane request after the
  /// native tunnel is up. A false result is a failed proof, never a warning.
  Future<bool> verifyVpnEgress({
    required String serverId,
    required int deviceId,
    required VpnProtocol protocol,
    required String baselineFingerprint,
  }) async {
    if (_config.useMockApi) return false;
    final response = await _dio.post<Map<String, dynamic>>(
      '/vpn/egress/verify',
      data: {
        'server_id': serverId,
        'device_id': deviceId,
        'protocol': vpnProtocolStorageValue(protocol),
        'baseline_fingerprint': baselineFingerprint,
      },
    );
    return response.data?['verified'] == true;
  }

  /// Notify the backend that the VPN tunnel has been established.
  ///
  /// In demo/mock mode this triggers the demo VPN session on the server so
  /// that the dashboard and status endpoints reflect a connected state.
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {
    if (_config.useMockApi) {
      _logMockApi();
      return;
    }
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
    if (_config.useMockApi) {
      _logMockApi();
      return;
    }
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
    if (_config.useMockApi) {
      _logMockApi();
      return;
    }
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
    if (_config.useMockApi) return null;
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
    if (_config.useMockApi) return;
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
    if (_config.useMockApi) return;
    await _dio.post<Map<String, dynamic>>(
      '/vpn/usage/sessions/$sessionId/disconnect',
      data: {'idempotency_key': idempotencyKey, 'reason': reason},
    );
  }

  void _logMockApi() {
    if (_mockNoticeLogged) return;
    _mockNoticeLogged = true;
    AppLogger.warning(
        'Mock API enabled: returning demo data instead of live endpoints.');
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
