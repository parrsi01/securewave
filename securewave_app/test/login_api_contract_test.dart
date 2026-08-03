import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
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
}
