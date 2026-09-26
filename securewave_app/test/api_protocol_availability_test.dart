import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  test('protocol availability keeps only WireGuard rows', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _ProtocolAdapter(includeWireGuard: true);
    final client = ApiClient(AppConfig.defaults(), dio: dio);

    final availability =
        await client.fetchProtocolAvailability(deviceType: 'linux');

    expect(availability.keys, [VpnProtocol.wireGuard]);
    expect(availability[VpnProtocol.wireGuard]?.enabled, isTrue);
  });

  test('missing WireGuard row fails closed', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _ProtocolAdapter(includeWireGuard: false);
    final client = ApiClient(AppConfig.defaults(), dio: dio);

    final availability =
        await client.fetchProtocolAvailability(deviceType: 'linux');

    expect(availability.keys, [VpnProtocol.wireGuard]);
    expect(availability[VpnProtocol.wireGuard]?.enabled, isFalse);
    expect(
      availability[VpnProtocol.wireGuard]?.reason,
      contains('WireGuard availability was not returned'),
    );
  });
}

class _ProtocolAdapter implements HttpClientAdapter {
  _ProtocolAdapter({required this.includeWireGuard});

  final bool includeWireGuard;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'protocols': [
        if (includeWireGuard)
          {
            'protocol': 'wireguard',
            'enabled': true,
            'server_enabled': true,
            'platform_supported': true,
          },
        {
          'protocol': 'removed-protocol',
          'enabled': true,
          'server_enabled': true,
          'platform_supported': true,
        },
      ],
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
