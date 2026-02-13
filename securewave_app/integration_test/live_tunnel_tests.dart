import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const bool _liveEnabled =
    bool.fromEnvironment('LIVE_NETWORK_TESTS', defaultValue: false);
const String _apiBaseUrl =
    String.fromEnvironment('LIVE_API_BASE_URL', defaultValue: '');
const String _password = String.fromEnvironment('LIVE_VALIDATION_PASSWORD',
    defaultValue: 'LiveValidate#123');

Future<HttpClientResponse> _jsonRequest(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, dynamic>? body,
  String? bearer,
}) async {
  final request = await client.openUrl(method, uri);
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  if (bearer != null && bearer.isNotEmpty) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  }
  if (body != null) {
    request.write(jsonEncode(body));
  }
  return request.close();
}

Future<Map<String, dynamic>> _decodeJson(HttpClientResponse response) async {
  final text = await utf8.decoder.bind(response).join();
  if (text.trim().isEmpty) {
    return <String, dynamic>{};
  }
  final parsed = jsonDecode(text);
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  return <String, dynamic>{};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live tunnel profile fetch from production backend',
      (tester) async {
    if (!_liveEnabled || _apiBaseUrl.isEmpty) {
      expect(true, isTrue, reason: 'LIVE_NETWORK_TESTS disabled');
      return;
    }

    final client = HttpClient();
    client.badCertificateCallback = (_, __, ___) => true;

    final runId = DateTime.now().microsecondsSinceEpoch;
    final email = 'live.flutter.$runId@example.com';
    String token = '';

    final registerUri = Uri.parse('$_apiBaseUrl/api/auth/register');
    final registerResponse = await _jsonRequest(
      client,
      'POST',
      registerUri,
      body: {
        'email': email,
        'password': _password,
        'password_confirm': _password,
      },
    );
    final registerBody = await _decodeJson(registerResponse);
    token = (registerBody['access_token'] ?? '').toString();

    if (token.isEmpty) {
      final loginUri = Uri.parse('$_apiBaseUrl/api/auth/login');
      final loginResponse = await _jsonRequest(
        client,
        'POST',
        loginUri,
        body: {
          'email': email,
          'password': _password,
        },
      );
      final loginBody = await _decodeJson(loginResponse);
      token = (loginBody['access_token'] ?? '').toString();
      expect(loginResponse.statusCode, 200);
      expect(token, isNotEmpty);
    }

    final profileUri = Uri.parse('$_apiBaseUrl/api/vpn/profile');
    final profileResponse = await _jsonRequest(
      client,
      'POST',
      profileUri,
      bearer: token,
      body: {
        'device_name': 'Flutter Live Integration',
        'device_type': Platform.operatingSystem,
        'protocol': 'wireguard',
      },
    );

    final profileBody = await _decodeJson(profileResponse);
    expect(profileResponse.statusCode, 200);

    final wireguardConfig = (profileBody['wireguard_config'] ?? '').toString();
    expect(wireguardConfig, contains('[Interface]'));
    expect(wireguardConfig, contains('[Peer]'));
    expect(wireguardConfig, contains('Endpoint = '));

    client.close(force: true);
  });
}
