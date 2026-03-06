import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../core/models/server_region.dart';
import '../core/models/user_plan.dart';
import '../core/services/auth_session.dart';
import '../core/services/vm_environment.dart';
import '../core/state/network_lock_state.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(authSessionProvider);
  final vmEnvironment = ref.watch(vmEnvironmentProvider);
  final networkLock = ref.watch(networkLockProvider);
  return ApiClient(
    config,
    session: session,
    vmEnvironment: vmEnvironment,
    networkLock: networkLock,
  );
});

class ApiClient {
  ApiClient(
    this._config, {
    AuthSession? session,
    VmEnvironment? vmEnvironment,
    NetworkLockState? networkLock,
  })  : _session = session,
        _vmEnvironment = vmEnvironment ??
            const VmEnvironment(
              isVirtualMachine: false,
              safeModeEnabled: false,
              reason: null,
            ),
        _networkLock = networkLock ?? const NetworkLockState() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _config.apiBaseUrl,
        connectTimeout: _vmEnvironment.safeModeEnabled
            ? const Duration(seconds: 12)
            : const Duration(seconds: 6),
        receiveTimeout: _vmEnvironment.safeModeEnabled
            ? const Duration(seconds: 20)
            : const Duration(seconds: 10),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _session?.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final AppConfig _config;
  final AuthSession? _session;
  final VmEnvironment _vmEnvironment;
  final NetworkLockState _networkLock;
  late final Dio _dio;
  List<ServerRegion>? _cachedServers;
  DateTime? _serversFetchedAt;
  UserPlan? _cachedPlan;
  DateTime? _planFetchedAt;

  static const Duration _serversCacheTtl = Duration(minutes: 5);
  static const Duration _planCacheTtl = Duration(minutes: 2);

  Future<void> healthCheck({bool allowWhenLocked = false}) async {
    _assertNetworkAllowed(allowWhenLocked: allowWhenLocked);
    if (_config.useMockApi) {
      return;
    }
    await _withRetry<void>(() async {
      await _dio.get<Map<String, dynamic>>('/api/health');
    });
  }

  Future<List<ServerRegion>> fetchServers({
    bool forceRefresh = false,
    bool allowWhenLocked = false,
  }) async {
    _assertNetworkAllowed(allowWhenLocked: allowWhenLocked);
    if (!forceRefresh && _cachedServers != null && _serversFetchedAt != null) {
      final age = DateTime.now().difference(_serversFetchedAt!);
      if (age < _serversCacheTtl) {
        return _cachedServers!;
      }
    }

    if (_config.useMockApi) {
      final data = _mockServers();
      _cachedServers = data;
      _serversFetchedAt = DateTime.now();
      return data;
    }

    try {
      final response = await _withRetry<Response<List<dynamic>>>(() {
        return _dio.get<List<dynamic>>('/vpn/servers');
      });
      final data = response.data ?? <dynamic>[];
      final servers = data
          .whereType<Map>()
          .map((entry) =>
              ServerRegion.fromJson(Map<String, dynamic>.from(entry)))
          .where((server) => server.id.isNotEmpty)
          .toList();
      if (servers.isEmpty) {
        throw const ApiClientException(
          'servers_empty',
          'Server discovery returned an empty list.',
        );
      }
      _cachedServers = servers;
      _serversFetchedAt = DateTime.now();
      await _saveServersCache(servers);
      return servers;
    } on ApiClientException catch (error, stackTrace) {
      AppLogger.error(
        'Server list fetch failed',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.server,
      );
      final cached = await _loadCachedServers();
      if (cached.isNotEmpty) {
        AppLogger.server(
          'Using cached server catalog',
          fields: <String, Object?>{'count': cached.length},
        );
        _cachedServers = cached;
        _serversFetchedAt = DateTime.now();
        return cached;
      }
      rethrow;
    }
  }

  Future<UserPlan> fetchUserPlan({
    bool forceRefresh = false,
    bool allowWhenLocked = false,
  }) async {
    _assertNetworkAllowed(allowWhenLocked: allowWhenLocked);
    if (!forceRefresh && _cachedPlan != null && _planFetchedAt != null) {
      final age = DateTime.now().difference(_planFetchedAt!);
      if (age < _planCacheTtl) {
        return _cachedPlan!;
      }
    }

    if (_config.useMockApi) {
      final plan = _mockPlan();
      _cachedPlan = plan;
      _planFetchedAt = DateTime.now();
      return plan;
    }

    final response = await _withRetry<Response<Map<String, dynamic>>>(() {
      return _dio.get<Map<String, dynamic>>('/user/plan');
    });
    final plan = UserPlan.fromJson(response.data ?? <String, dynamic>{});
    _cachedPlan = plan;
    _planFetchedAt = DateTime.now();
    return plan;
  }

  Future<AuthTokens> login(
      {required String email, required String password}) async {
    _assertNetworkAllowed();
    if (_config.useMockApi) {
      return _mockTokens(email);
    }

    final response = await _withRetry<Response<Map<String, dynamic>>>(() {
      return _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
    });
    return _parseTokens(response.data,
        fallbackMessage: 'Login did not return an access token.');
  }

  Future<AuthTokens?> register(
      {required String email, required String password}) async {
    _assertNetworkAllowed();
    if (_config.useMockApi) {
      return _mockTokens(email);
    }

    final response = await _withRetry<Response<Map<String, dynamic>>>(() {
      return _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'password_confirm': password,
        },
      );
    });
    if (response.data?['access_token'] == null) {
      return null;
    }
    return _parseTokens(
      response.data,
      fallbackMessage: 'Registration did not return an access token.',
    );
  }

  Future<String> fetchVpnProfile({
    String? serverId,
    bool allowWhenLocked = false,
  }) async {
    _assertNetworkAllowed(allowWhenLocked: allowWhenLocked);
    if (_config.useMockApi) {
      return _mockVpnProfile();
    }

    final response = await _withRetry<Response<Map<String, dynamic>>>(() {
      return _dio.post<Map<String, dynamic>>(
        '/vpn/profile',
        data: {
          if (serverId != null && serverId.isNotEmpty) 'server_id': serverId,
        },
      );
    });
    final data = response.data ?? const <String, dynamic>{};
    final profile = data['profile'] ?? data['config'];
    if (profile is String && profile.trim().isNotEmpty) {
      return profile;
    }
    throw const ApiClientException(
      'profile_missing',
      'VPN profile response did not include a usable profile payload.',
    );
  }

  Future<T> _withRetry<T>(Future<T> Function() request) async {
    final attempts = _vmEnvironment.safeModeEnabled ? 4 : 3;
    final baseDelay = _vmEnvironment.safeModeEnabled ? 1200 : 500;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await request();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final shouldRetry = _isTransient(error) && attempt < attempts;
        if (!shouldRetry) {
          break;
        }
        AppLogger.warning(
            'API request retry $attempt/$attempts after transient failure.');
        await Future<void>.delayed(Duration(milliseconds: baseDelay * attempt));
      }
    }

    if (lastError is DioException) {
      throw ApiClientException.fromDio(lastError);
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  void _assertNetworkAllowed({bool allowWhenLocked = false}) {
    if (allowWhenLocked || !_networkLock.isLocked) {
      return;
    }
    throw ApiClientException(
      'kill_switch_active',
      _networkLock.reason ??
          'Best-effort kill switch is blocking new app traffic.',
    );
  }

  bool _isTransient(Object error) {
    if (error is! DioException) {
      return false;
    }
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        (error.response?.statusCode != null &&
            error.response!.statusCode! >= 500);
  }

  AuthTokens _parseTokens(
    Map<String, dynamic>? data, {
    required String fallbackMessage,
  }) {
    final accessToken = data?['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw ApiClientException('token_missing', fallbackMessage);
    }
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: data?['refresh_token']?.toString(),
    );
  }

  AuthTokens _mockTokens(String email) {
    final handle = email.split('@').first;
    return AuthTokens(
      accessToken: 'mock-token-$handle',
      refreshToken: 'mock-refresh-$handle',
    );
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

  Future<File> _serverCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/securewave_servers_cache.json');
  }

  Future<void> _saveServersCache(List<ServerRegion> servers) async {
    try {
      final file = await _serverCacheFile();
      await file.parent.create(recursive: true);
      final payload = <Map<String, Object?>>[
        for (final server in servers)
          <String, Object?>{
            'id': server.id,
            'name': server.name,
            'city': server.city,
            'country': server.country,
            'latency_ms': server.latencyMs,
          },
      ];
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Failed to save server cache',
        category: AppLogCategory.server,
        fields: <String, Object?>{'error': error.toString()},
      );
      AppLogger.error(
        'Server cache write failed',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.server,
      );
    }
  }

  Future<List<ServerRegion>> _loadCachedServers() async {
    try {
      final file = await _serverCacheFile();
      if (!await file.exists()) {
        return const <ServerRegion>[];
      }
      final payload = jsonDecode(await file.readAsString());
      if (payload is! List) {
        return const <ServerRegion>[];
      }
      return payload
          .whereType<Map>()
          .map(
            (entry) => ServerRegion.fromJson(
              <String, dynamic>{
                'id': entry['id'],
                'name': entry['name'],
                'city': entry['city'],
                'country': entry['country'],
                'latency_ms': entry['latency_ms'],
              },
            ),
          )
          .where((server) => server.id.isNotEmpty)
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
        'Server cache read failed',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.server,
      );
      return const <ServerRegion>[];
    }
  }

  UserPlan _mockPlan() {
    return const UserPlan(
      name: 'Free',
      isPremium: false,
      dataCapGb: 5,
      usedGb: 1.6,
    );
  }

  String _mockVpnProfile() {
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

class ApiClientException implements Exception {
  const ApiClientException(this.code, this.message);

  final String code;
  final String message;

  factory ApiClientException.fromDio(DioException error) {
    final code = error.response?.statusCode?.toString() ?? error.type.name;
    final data = error.response?.data;
    final message = data is Map<String, dynamic>
        ? (data['detail']?.toString() ??
            data['message']?.toString() ??
            error.message ??
            'API request failed.')
        : (error.message ?? 'API request failed.');
    return ApiClientException(code, message);
  }

  @override
  String toString() => 'ApiClientException($code): $message';
}
