import 'dart:convert';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class WireGuardConfigParameters {
  const WireGuardConfigParameters({
    required this.address,
    required this.dns,
    required this.serverPublicKey,
    required this.endpoint,
    required this.allowedIps,
    required this.keepalive,
    required this.location,
  });

  final String address;
  final String? dns;
  final String serverPublicKey;
  final String endpoint;
  final String allowedIps;
  final int? keepalive;
  final String location;

  factory WireGuardConfigParameters.fromJson(Map<String, dynamic> json) {
    final source = json['wireguard_config']?.toString() ?? '';
    if (source.trim().isEmpty) {
      throw const ApiException(
          'SecureWave returned an empty WireGuard config.');
    }

    Map<String, String>? current;
    Map<String, String>? interface;
    Map<String, String>? peer;
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line == '[Interface]') {
        if (interface != null || peer != null) {
          throw const ApiException(
              'SecureWave returned an invalid WireGuard config.');
        }
        current = interface = {};
        continue;
      }
      if (line == '[Peer]') {
        if (interface == null || peer != null) {
          throw const ApiException(
              'SecureWave returned an invalid WireGuard config.');
        }
        current = peer = {};
        continue;
      }
      final separator = line.indexOf('=');
      if (current == null || separator < 1) {
        throw const ApiException(
            'SecureWave returned an invalid WireGuard config.');
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (current.containsKey(key)) {
        throw const ApiException(
            'SecureWave returned an invalid WireGuard config.');
      }
      if (current == interface && key == 'privatekey') {
        if (value.isNotEmpty) {
          throw const ApiException(
            'SecureWave returned a server-side private key; connection was stopped.',
          );
        }
        continue;
      }
      final allowed = current == interface
          ? const {'address', 'dns'}
          : const {
              'publickey',
              'endpoint',
              'allowedips',
              'persistentkeepalive'
            };
      if (!allowed.contains(key) || !_safeValue(value)) {
        throw const ApiException(
            'SecureWave returned unsupported WireGuard settings.');
      }
      current[key] = value;
    }

    final address = interface?['address'];
    final serverPublicKey = peer?['publickey'];
    final endpoint = peer?['endpoint'];
    final allowedIps = peer?['allowedips'];
    if (address == null ||
        !_safeNetworkList(address) ||
        serverPublicKey == null ||
        !_safeKey(serverPublicKey) ||
        endpoint == null ||
        !_safeEndpoint(endpoint) ||
        allowedIps == null ||
        !_safeNetworkList(allowedIps)) {
      throw const ApiException(
          'SecureWave returned incomplete WireGuard settings.');
    }
    final dns = interface?['dns'];
    if (dns != null && !_safeNetworkList(dns)) {
      throw const ApiException('SecureWave returned invalid DNS settings.');
    }
    final keepaliveText = peer?['persistentkeepalive'];
    final keepalive =
        keepaliveText == null ? null : int.tryParse(keepaliveText);
    if (keepaliveText != null &&
        (keepalive == null || keepalive < 0 || keepalive > 3600)) {
      throw const ApiException(
          'SecureWave returned invalid WireGuard settings.');
    }
    final rawLocation = json['server_location']?.toString().trim();

    return WireGuardConfigParameters(
      address: address,
      dns: dns,
      serverPublicKey: serverPublicKey,
      endpoint: endpoint,
      allowedIps: allowedIps,
      keepalive: keepalive,
      location:
          rawLocation == null || rawLocation.isEmpty || !_safeValue(rawLocation)
              ? 'Germany'
              : rawLocation,
    );
  }

  String toClientConfig(String privateKey) {
    if (!_safeKey(privateKey)) {
      throw const ApiException('The local WireGuard key could not be used.');
    }
    return [
      '[Interface]',
      'PrivateKey = $privateKey',
      'Address = $address',
      if (dns != null) 'DNS = $dns',
      '',
      '[Peer]',
      'PublicKey = $serverPublicKey',
      'Endpoint = $endpoint',
      'AllowedIPs = $allowedIps',
      if (keepalive != null && keepalive! > 0)
        'PersistentKeepalive = $keepalive',
      '',
    ].join('\n');
  }

  static bool _safeValue(String value) =>
      value.isNotEmpty && !value.contains('\n') && !value.contains('\r');

  static bool _safeKey(String value) =>
      RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value);

  static bool _safeNetworkList(String value) =>
      value.isNotEmpty && RegExp(r'^[0-9A-Fa-f:.,/\s]+$').hasMatch(value);

  static bool _safeEndpoint(String value) => RegExp(
        r'^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\]):[1-9][0-9]{0,4}$',
      ).hasMatch(value);
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

  Future<void> register({
    required String email,
    required String password,
  }) async {
    await _request(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password},
    );
  }

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

  Future<String> currentUserId() async {
    final data = await _request('GET', '/auth/me');
    final id = data['id'];
    if (id is num && id > 0) return id.toString();
    throw const ApiException('Could not identify the SecureWave account.');
  }

  Future<WireGuardConfigParameters> fetchWireGuardConfig({
    required String publicKey,
  }) async {
    final data = await _request(
      'POST',
      '/vpn/config',
      body: {'public_key': publicKey},
    );
    return WireGuardConfigParameters.fromJson(data);
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
      if (statusCode >= 400) {
        throw ApiException(_errorMessage(statusCode), statusCode: statusCode);
      }
      final payload = response.data;
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return const {};
    } on DioException {
      throw const ApiException(
        'Unable to reach SecureWave. Check your connection and try again.',
      );
    }
  }

  String _errorMessage(int statusCode) {
    if (statusCode == 401) return 'Invalid email or password.';
    if (statusCode == 409) {
      return 'An account with this email already exists.';
    }
    if (statusCode == 400 || statusCode == 422) {
      return 'Check the email and password fields and try again.';
    }
    if (statusCode == 429) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (statusCode >= 500) return 'SecureWave server error.';
    return 'SecureWave could not complete the request (HTTP $statusCode).';
  }
}
