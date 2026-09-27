import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/api_service.dart';
import 'package:securewave_app/services/vpn_service.dart';

void main() {
  group('registration request', () {
    test('sends only email and password to the production route', () async {
      final adapter = _TestAdapter(201, {'message': 'created'});
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.test/api',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = adapter;
      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.next(options);
          },
        ),
      );

      await ApiService(dio: dio).register(
        email: 'person@example.com',
        password: 'passphrase1',
      );

      expect(captured?.path, '/auth/register');
      expect(captured?.data, {
        'email': 'person@example.com',
        'password': 'passphrase1',
      });
    });

    test('reports an existing account safely', () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://api.test/api',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = _TestAdapter(409, {'detail': 'internal text'});

      await expectLater(
        ApiService(dio: dio).register(
          email: 'person@example.com',
          password: 'passphrase1',
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'An account with this email already exists.',
          ),
        ),
      );
    });
  });

  test('login returns a token that authenticates the current-user request',
      () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.test/api',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _TestAdapter(200, {
        'access_token': 'session-token',
        'token_type': 'bearer',
      });
    RequestOptions? captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ),
    );
    final api = ApiService(dio: dio);

    final token = await api.login(
      email: 'person@example.com',
      password: 'passphrase1',
    );
    expect(token, 'session-token');
    expect(captured?.path, '/auth/login');
    expect(captured?.data, {
      'email': 'person@example.com',
      'password': 'passphrase1',
    });

    api.setAccessToken(token);
    dio.httpClientAdapter = _TestAdapter(200, {'id': 1});
    await api.checkSession();

    expect(captured?.path, '/auth/me');
    expect(captured?.headers['Authorization'], 'Bearer session-token');
  });

  group('WireGuard configuration', () {
    test('adds the locally generated private key to server parameters', () {
      final parameters = WireGuardConfigParameters.fromJson({
        'server_location': 'Germany',
        'wireguard_config': '''
[Interface]
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 198.51.100.7:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''',
      });
      final config = parameters.toClientConfig(
        'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
      );

      expect(parameters.location, 'Germany');
      expect(config, contains('PrivateKey = BBBB'));
      expect(config, isNot(contains('PrivateKey = AAAAA')));
      expect(config, contains('PublicKey = AAAAA'));
      expect(config, contains('Endpoint = 198.51.100.7:51820'));
    });

    test('rejects private keys and commands returned by the API', () {
      expect(
        () => WireGuardConfigParameters.fromJson({
          'wireguard_config': '''
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.0.0.2/32

[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
Endpoint = 198.51.100.7:51820
AllowedIPs = 0.0.0.0/0
''',
        }),
        throwsA(isA<ApiException>()),
      );

      expect(
        () => WireGuardConfigParameters.fromJson({
          'wireguard_config': '''
[Interface]
Address = 10.0.0.2/32
PostUp = touch /tmp/marker

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 198.51.100.7:51820
AllowedIPs = 0.0.0.0/0
''',
        }),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('provisions a peer with only the public key and bearer token', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.test/api',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _TestAdapter(200, {
        'wireguard_config': '''
[Interface]
Address = 10.0.0.2/32

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 198.51.100.7:51820
AllowedIPs = 0.0.0.0/0
''',
      });
    RequestOptions? captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ),
    );
    final api = ApiService(dio: dio)..setAccessToken('session-token');

    await api.fetchWireGuardConfig(
      publicKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    );

    expect(captured?.path, '/vpn/config');
    expect(captured?.method, 'POST');
    expect(captured?.data, {
      'public_key': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    });
    expect(captured?.headers['Authorization'], 'Bearer session-token');
  });

  group('WireGuard traffic counters', () {
    test('parses receive and transmit counters from the Linux helper', () {
      final stats = VpnTrafficStats.fromMap({
        'rx_bytes': '2048',
        'tx_bytes': 512,
        'counters_available': true,
      });

      expect(stats.available, isTrue);
      expect(stats.rxBytes, 2048);
      expect(stats.txBytes, 512);
    });

    test('does not report unavailable counters as zero usage', () {
      final stats = VpnTrafficStats.fromMap({
        'rx_bytes': 0,
        'tx_bytes': 0,
        'counters_available': false,
      });

      expect(stats.available, isFalse);
    });
  });
}

class _TestAdapter implements HttpClientAdapter {
  _TestAdapter(this.statusCode, this.payload);

  final int statusCode;
  final Object payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(payload),
        statusCode,
        headers: const {
          'content-type': ['application/json']
        },
      );

  @override
  void close({bool force = false}) {}
}
