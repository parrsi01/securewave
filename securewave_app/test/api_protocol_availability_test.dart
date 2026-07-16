import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  test('stale protocol payload cannot advertise OpenVPN', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _ProtocolAdapter(runtimeContract: 'legacy');
    final client = ApiClient(AppConfig.defaults(), dio: dio);

    final availability =
        await client.fetchProtocolAvailability(deviceType: 'linux');

    expect(availability[VpnProtocol.wireGuard]?.enabled, isTrue);
    expect(availability[VpnProtocol.openVpn]?.enabled, isFalse);
    expect(
      availability[VpnProtocol.openVpn]?.reason,
      contains('stale'),
    );
    expect(availability[VpnProtocol.ikev2]?.enabled, isFalse);
  });

  test('current evidence contract preserves OpenVPN availability metadata',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _ProtocolAdapter(
        runtimeContract: ApiClient.openVpnRuntimeContract,
      );
    final client = ApiClient(AppConfig.defaults(), dio: dio);

    final availability =
        await client.fetchProtocolAvailability(deviceType: 'linux');

    expect(availability[VpnProtocol.openVpn]?.enabled, isTrue);
    expect(availability[VpnProtocol.ikev2]?.platformSupported, isFalse);
  });
}

class _ProtocolAdapter implements HttpClientAdapter {
  _ProtocolAdapter({required this.runtimeContract});

  final String runtimeContract;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'runtime_contract': runtimeContract,
      'protocols': [
        {
          'protocol': 'wireguard',
          'enabled': true,
          'server_enabled': true,
          'platform_supported': true,
        },
        {
          'protocol': 'openvpn',
          'enabled': true,
          'server_enabled': true,
          'platform_supported': true,
        },
        {
          'protocol': 'ikev2',
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
