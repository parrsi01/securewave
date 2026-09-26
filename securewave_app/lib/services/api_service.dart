import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class WireGuardProfile {
  const WireGuardProfile({
    required this.deviceId,
    required this.serverId,
    required this.location,
    required this.config,
  });

  final int deviceId;
  final String serverId;
  final String location;
  final String config;

  factory WireGuardProfile.fromJson(Map<String, dynamic> json) {
    final config = json['wireguard_config']?.toString().trim() ?? '';
    if (config.isEmpty) {
      throw const ApiException('The API returned an empty WireGuard profile.');
    }
    return WireGuardProfile(
      deviceId: int.tryParse('${json['device_id']}') ?? 0,
      serverId: json['server_id']?.toString() ?? '',
      location: json['server_location']?.toString() ?? 'Automatic',
      config: config,
    );
  }
}

class ApiService {
  ApiService({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? apiBaseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: {'Content-Type': 'application/json'},
                validateStatus: (_) => true,
              ),
            );

  static const apiBaseUrl = String.fromEnvironment(
    'SECUREWAVE_API_BASE_URL',
    defaultValue: 'https://api.securewaveapp.com/api',
  );

  final Dio _dio;
  String? _accessToken;

  void setAccessToken(String? token) => _accessToken = token;

  Future<String> login({
    required String email,
    required String password,
  }) =>
      _authenticate('/auth/login', {
        'email': email,
        'password': password,
      });

  Future<String> register({
    required String email,
    required String password,
  }) =>
      _authenticate('/auth/register', {
        'email': email,
        'password': password,
        'password_confirm': password,
      });

  Future<String> _authenticate(String path, Map<String, dynamic> body) async {
    final data = await _request('POST', path, body: body, authenticated: false);
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException('The API did not return a sign-in token.');
    }
    return token;
  }

  Future<void> checkSession() async {
    await _request('GET', '/auth/me');
  }

  Future<void> logout() async {
    await _request('POST', '/auth/logout');
  }

  Future<WireGuardProfile> fetchWireGuardProfile({
    required String deviceName,
  }) async {
    final availability = await _request(
      'GET',
      '/vpn/protocols',
      queryParameters: {'device_type': 'linux'},
    );
    final protocols = availability['protocols'];
    Map? wireGuard;
    if (protocols is List) {
      for (final entry in protocols.whereType<Map>()) {
        if (entry['protocol']?.toString().toLowerCase() == 'wireguard') {
          wireGuard = entry;
          break;
        }
      }
    }
    if (wireGuard?['enabled'] != true) {
      final reason = wireGuard?['reason']?.toString();
      throw ApiException(
        reason == null || reason.isEmpty
            ? 'No WireGuard server is available.'
            : reason,
      );
    }

    final profile = await _request(
      'POST',
      '/vpn/profile',
      body: {
        'device_name': deviceName,
        'device_type': 'linux',
        'protocol': 'wireguard',
      },
    );
    return WireGuardProfile.fromJson(profile);
  }

  Future<void> notifyConnected(WireGuardProfile profile) async {
    await _request(
      'POST',
      '/vpn/connect',
      body: {
        'server_id': profile.serverId,
        'region': profile.serverId,
        'protocol': 'wireguard',
      },
    );
  }

  Future<void> notifyDisconnected() async {
    await _request('POST', '/vpn/disconnect');
  }

  Future<int?> startUsageSession(WireGuardProfile profile) async {
    final data = await _request(
      'POST',
      '/vpn/usage/sessions/start',
      body: {
        'device_id': profile.deviceId,
        'server_id': profile.serverId,
        'protocol': 'wireguard',
        'idempotency_key':
            'client-start-${profile.deviceId}-${DateTime.now().microsecondsSinceEpoch}',
      },
    );
    final value = data['session_id'];
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  Future<void> reportUsage({
    required int sessionId,
    required int sequence,
    required int bytesSent,
    required int bytesReceived,
  }) async {
    await _request(
      'POST',
      '/vpn/usage/sessions/$sessionId/increment',
      body: {
        'sequence': sequence,
        'bytes_sent': bytesSent,
        'bytes_received': bytesReceived,
        'idempotency_key': 'client-increment-$sessionId-$sequence',
      },
    );
  }

  Future<void> finishUsageSession(int sessionId) async {
    await _request(
      'POST',
      '/vpn/usage/sessions/$sessionId/disconnect',
      body: {
        'idempotency_key':
            'client-disconnect-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
        'reason': 'client_disconnect',
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            if (authenticated &&
                _accessToken != null &&
                _accessToken!.isNotEmpty)
              'Authorization': 'Bearer $_accessToken',
          },
        ),
      );
      final statusCode = response.statusCode ?? 0;
      final payload = response.data;
      if (statusCode >= 400) {
        throw ApiException(_errorMessage(payload), statusCode: statusCode);
      }
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return const {};
    } on DioException {
      throw const ApiException('Could not reach the SecureWave API.');
    }
  }

  String _errorMessage(Object? payload) {
    if (payload is Map) {
      final detail = payload['detail'] ?? payload['message'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
    }
    return 'The SecureWave API request failed.';
  }
}
