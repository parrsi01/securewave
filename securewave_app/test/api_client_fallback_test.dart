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

  test('ApiClient does not fall back to mock data when the backend is unreachable', () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
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
  });
}
