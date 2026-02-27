import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/services/api_client.dart';

Dio stubDio(Map<String, dynamic> Function(RequestOptions options) resolver) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final payload = resolver(options);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: payload,
          ),
        );
      },
    ),
  );
  return dio;
}

AppConfig testConfig() => AppConfig(
      apiBaseUrl: 'http://localhost:8000',
      portalUrl: 'http://localhost:8000',
      upgradeUrl: 'http://localhost:8000',
      resetSessionOnBoot: false,
      devLoginAccounts: const <DevLoginAccount>[],
    );

void main() {
  test('fetchServers throws in dev when region health fields are missing',
      () async {
    final client = ApiClient(
      testConfig(),
      dio: stubDio((options) {
        if (options.path == '/vpn/regions') {
          return <String, dynamic>{
            'regions': <Map<String, dynamic>>[
              <String, dynamic>{
                'server_id': 'us-east-1',
                'name': 'US East',
              },
            ],
            'total': 1,
          };
        }
        return <String, dynamic>{};
      }),
    );

    await expectLater(
      client.fetchServers(forceRefresh: true),
      throwsA(isA<StateError>()),
    );
  });

  test('fetchUserPlan throws in dev when usage contract is broken', () async {
    final client = ApiClient(
      testConfig(),
      dio: stubDio((options) {
        if (options.path == '/account/usage') {
          return <String, dynamic>{
            'used_bytes': 100,
            'plan_tier': 'free',
          };
        }
        return <String, dynamic>{};
      }),
    );

    await expectLater(
      client.fetchUserPlan(forceRefresh: true),
      throwsA(isA<StateError>()),
    );
  });

  test('fetchVpnProtocols throws in dev when required flags are missing',
      () async {
    final client = ApiClient(
      testConfig(),
      dio: stubDio((options) {
        if (options.path == '/vpn/protocols') {
          return <String, dynamic>{
            'user_tier': 'free',
            'device_type': 'linux',
            'protocols': <Map<String, dynamic>>[
              <String, dynamic>{
                'protocol': 'wireguard',
                'enabled': true,
                'server_enabled': true,
                'platform_supported': true,
              },
            ],
          };
        }
        return <String, dynamic>{};
      }),
    );

    await expectLater(
      client.fetchVpnProtocols(deviceType: 'linux'),
      throwsA(isA<StateError>()),
    );
  });
}
