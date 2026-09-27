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

  group('WireGuard API profile', () {
    test('reads the real server profile fields', () {
      final profile = WireGuardProfile.fromJson({
        'device_id': 17,
        'server_id': 'hetzner-eu-1',
        'server_location': 'Helsinki, Finland',
        'wireguard_config': '[Interface]\nAddress = 10.0.0.2/32',
      });

      expect(profile.deviceId, 17);
      expect(profile.serverId, 'hetzner-eu-1');
      expect(profile.location, 'Helsinki, Finland');
      expect(profile.config, contains('[Interface]'));
    });

    test('rejects an empty tunnel configuration', () {
      expect(
        () => WireGuardProfile.fromJson({'wireguard_config': '  '}),
        throwsA(isA<ApiException>()),
      );
    });
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
