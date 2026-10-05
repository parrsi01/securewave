import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:securewave_app/app.dart';
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

      await (ApiService(dio: dio)..setAccessToken('expired-session')).register(
        email: 'person@example.com',
        password: 'passphrase1',
      );

      expect(captured?.path, '/auth/register');
      expect(captured?.headers.containsKey('Authorization'), isFalse);
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

    test('recognizes the production HTTP 400 duplicate-account envelope',
        () async {
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _TestAdapter(400, {
          'error': {
            'code': 'http_error',
            'message': 'Email already registered',
          },
        });
      await expectLater(
        ApiService(dio: dio).register(
          email: 'person@example.com',
          password: 'passphrase1',
        ),
        throwsA(isA<ApiException>().having(
          (error) => error.message,
          'message',
          'An account with this email already exists.',
        )),
      );
    });
  });

  group('unauthorized responses', () {
    late ApiService api;
    setUp(() {
      final dio = Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = _TestAdapter(401, {
          'error': {'message': 'private server detail'},
        });
      api = ApiService(dio: dio);
    });

    test('rejects incorrect login credentials', () async {
      await expectLater(
        api.login(email: 'person@example.com', password: 'incorrect'),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.message, 'message',
                'Invalid email or password.')),
      );
    });

    test('does not report a registration 401 as incorrect credentials',
        () async {
      await expectLater(
        api.register(email: 'person@example.com', password: 'passphrase1'),
        throwsA(isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having((error) => error.message, 'message',
                'SecureWave could not authorize account creation. Please try again later.')),
      );
    });

    test('identifies rejected protected sessions for sign-out', () async {
      api.setAccessToken('expired-session');
      await expectLater(
        api.checkSession(),
        throwsA(isA<ApiException>()
            .having((error) => error.unauthorized, 'unauthorized', isTrue)
            .having((error) => error.message, 'message',
                'Your session has expired. Sign in again.')),
      );
    });
  });

  testWidgets('an expired saved session opens sign-in and clears its token',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'expired'});
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = _TestAdapter(401, {'detail': 'Invalid token'});
    await tester.pumpWidget(SecureWaveApp(api: ApiService(dio: dio)));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Your session has expired. Sign in to continue.'),
        findsOneWidget);
    expect(
        await const FlutterSecureStorage().read(key: 'access_token'), isNull);
  });

  testWidgets('a fresh installation still opens create-account',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SecureWaveApp());
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsNWidgets(2));
    expect(find.text('Your session has expired. Sign in to continue.'),
        findsNothing);
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

  test('persistent usage retries reuse the start key and reporting capability',
      () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter =
          _TestAdapter(200, {'session_id': 123, 'metering_version': 2});
    final requests = <Map<String, dynamic>>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.endsWith('/usage/sessions/start')) {
        requests.add(Map<String, dynamic>.from(options.data as Map));
        if (requests.length == 1) {
          handler.reject(DioException(requestOptions: options));
          return;
        }
      }
      handler.next(options);
    }));
    final api = ApiService(dio: dio);
    const parameters = WireGuardConfigParameters(
      address: '10.8.0.10/32',
      dns: '1.1.1.1',
      serverPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      endpoint: 'vpn.example.test:51820',
      allowedIps: '0.0.0.0/0',
      keepalive: 25,
      location: 'Germany',
      deviceId: 4,
      serverId: 'server-1',
    );
    final session = await api.startUsage(parameters);
    expect(session.id, 123);
    expect(requests.length, 2);
    expect(requests[0], requests[1]);
    expect(requests[0]['reporting_token'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(requests[0]['metering_version'], 2);
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

  group('WireGuard runtime status from Linux helper', () {
    const serverKey = 'w1bQ0wAmvob32mgEBQvVkTTAu10bSmyK7bGkC/06pGA=';

    test('parses fixed interface, peer handshake, and real counters', () {
      final runtime = WireGuardRuntimeSnapshot.fromMap({
        'status': 'connected',
        'interface': 'sw-wg',
        'rx_bytes': 2048,
        'tx_bytes': 512,
        'counters_available': true,
        'peer_handshakes': '$serverKey 1770000000\n',
      });

      expect(runtime.status, VpnStatus.connected);
      expect(runtime.interfaceName, 'sw-wg');
      expect(runtime.peerLatestHandshakes[serverKey], 1770000000);
      expect(runtime.rxBytes, 2048);
      expect(runtime.txBytes, 512);
      expect(runtime.countersAvailable, isTrue);
    });

    test('rejects a mismatched interface or malformed handshake row', () {
      final base = <String, Object>{
        'status': 'connected',
        'interface': 'sw-wg',
        'rx_bytes': 10,
        'tx_bytes': 20,
        'counters_available': true,
        'peer_handshakes': '$serverKey 1770000000\n',
      };

      expect(
        () => WireGuardRuntimeSnapshot.fromMap({...base, 'interface': 'eth0'}),
        throwsA(isA<VpnServiceException>()),
      );
      expect(
        () => WireGuardRuntimeSnapshot.fromMap({
          ...base,
          'peer_handshakes': 'not-a-public-key 1770000000\n',
        }),
        throwsA(isA<VpnServiceException>()),
      );
    });

    test('rejects connected state without readable counters', () {
      expect(
        () => WireGuardRuntimeSnapshot.fromMap({
          'status': 'connected',
          'interface': 'sw-wg',
          'rx_bytes': 0,
          'tx_bytes': 0,
          'counters_available': false,
          'peer_handshakes': '',
        }),
        throwsA(isA<VpnServiceException>()),
      );
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
