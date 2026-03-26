import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/services/api_client.dart';

AppConfig _testConfig() => AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      resetSessionOnBoot: false,
    );

void main() {
  test(
      'fetchHealth retries transient connection-closed transport resets and succeeds',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    var attempts = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          attempts += 1;
          if (attempts < 3) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
                error: const HttpException(
                  'Connection closed before full header was received',
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const <String, dynamic>{
                'status': 'ok',
                'service': 'securewave',
              },
            ),
          );
        },
      ),
    );

    final client = ApiClient(_testConfig(), dio: dio);
    final response = await client.fetchHealth();

    expect(response['status'], 'ok');
    expect(attempts, 3);
  });
}
