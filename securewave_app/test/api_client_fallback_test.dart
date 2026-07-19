import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  Dio failingDio(String baseUrl) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: Exception('boom'),
            ),
          );
        },
      ),
    );
    return dio;
  }

  test('ApiClient does not fall back to mock data when mock API is disabled',
      () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, dio: failingDio(config.apiBaseUrl));

    await expectLater(
      client.login(email: 'a@b.com', password: 'pw'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.register(email: 'a@b.com', password: 'pw'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchServers(forceRefresh: true),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchUserPlan(forceRefresh: true),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchCurrentUser(),
      throwsA(isA<DioException>()),
    );
  });

  test('ApiClient returns mock data when mock API is enabled', () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: true,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, dio: failingDio(config.apiBaseUrl));

    final tokens =
        await client.login(email: 'alice@example.com', password: 'pw');
    expect(tokens.accessToken, contains('mock-token-'));

    final servers = await client.fetchServers(forceRefresh: true);
    expect(servers, isNotEmpty);

    final plan = await client.fetchUserPlan(forceRefresh: true);
    expect(plan.name, isNotEmpty);

    final account = await client.fetchCurrentUser();
    expect(account.email, isNotEmpty);
  });

  test('server catalog request carries the Linux device contract', () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: <String, dynamic>{'servers': <dynamic>[]},
            ),
          );
        },
      ),
    );
    final client = ApiClient(config, dio: dio);

    await client.fetchServers(forceRefresh: true, deviceType: 'linux');

    expect(requests.single.path, '/vpn/servers');
    expect(requests.single.queryParameters['device_type'], 'linux');
  });
}
