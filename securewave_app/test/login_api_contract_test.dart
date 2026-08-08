import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/logging/app_logger.dart';
import 'package:securewave_app/core/utils/api_error.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  test('login targets the API route and surfaces a nested 401 message',
      () async {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.test/api',
      portalUrl: 'https://example.test',
      upgradeUrl: 'https://example.test',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    late Uri requestedUri;
    final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedUri = options.uri;
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {
                    'code': 'http_error',
                    'message': 'Invalid credentials',
                  },
                  'request_id': 'test-request-id',
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    final client = ApiClient(config, dio: dio);
    DioException? caught;
    try {
      await client.login(email: 'user@example.test', password: 'password');
    } on DioException catch (error) {
      caught = error;
    }

    expect(requestedUri.toString(), 'https://api.example.test/api/auth/login');
    expect(caught, isNotNull);
    expect(ApiError.messageFrom(caught!), 'Invalid credentials');
  });

  test('diagnostic login logging excludes request secrets', () async {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.test/api',
      portalUrl: 'https://example.test',
      upgradeUrl: 'https://example.test',
      useMockApi: false,
      resetSessionOnBoot: false,
      diagnosticsEnabled: true,
    );
    final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 403,
                data: {
                  'detail': 'Please verify your email before logging in',
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    AppLogger.logStream.value = <AppLogEntry>[];
    AppLogger.errorStream.value = null;
    final client = ApiClient(config, dio: dio);
    try {
      await client.login(
        email: 'secret-user@example.test',
        password: 'secret-password',
      );
      fail('login should fail');
    } on DioException {
      // The original transport error remains available to the caller.
    }

    final logText =
        AppLogger.logStream.value.map((entry) => entry.message).join('\n');
    expect(logText, contains('category=forbidden'));
    expect(logText, isNot(contains('https://api.example.test/api')));
    expect(logText, isNot(contains('authorization')));
    expect(logText, isNot(contains('secret-user@example.test')));
    expect(logText, isNot(contains('secret-password')));
    expect(AppLogger.errorStream.value?.error, isNull);
  });

  test('successful login returns tokens without diagnostic token leakage',
      () async {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.test/api',
      portalUrl: 'https://example.test',
      upgradeUrl: 'https://example.test',
      useMockApi: false,
      resetSessionOnBoot: false,
      diagnosticsEnabled: true,
    );
    final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'access_token': 'access-token-secret',
                'refresh_token': 'refresh-token-secret',
                'requires_2fa': false,
              },
            ),
          );
        },
      ),
    );

    AppLogger.logStream.value = <AppLogEntry>[];
    final tokens = await ApiClient(config, dio: dio).login(
      email: 'successful-user@example.test',
      password: 'successful-password',
    );

    expect(tokens.accessToken, 'access-token-secret');
    final logText =
        AppLogger.logStream.value.map((entry) => entry.message).join('\n');
    expect(logText, contains('category=access_token_received'));
    expect(logText, isNot(contains('access-token-secret')));
    expect(logText, isNot(contains('refresh-token-secret')));
    expect(logText, isNot(contains('successful-user@example.test')));
    expect(logText, isNot(contains('successful-password')));
  });
}
