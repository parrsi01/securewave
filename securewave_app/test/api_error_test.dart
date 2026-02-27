import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/utils/api_error.dart';

void main() {
  group('ApiError.messageFrom', () {
    RequestOptions requestOptions() => RequestOptions(path: '/auth/login');

    test('uses nested error.message when backend wraps failures', () {
      final error = DioException(
        requestOptions: requestOptions(),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions(),
          statusCode: 401,
          data: const {
            'error': {
              'code': 'unauthorized',
              'message': 'Invalid credentials',
            },
          },
        ),
      );

      expect(
        ApiError.messageFrom(error),
        'Invalid credentials',
      );
    });

    test('uses validation detail list message', () {
      final error = DioException(
        requestOptions: requestOptions(),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions(),
          statusCode: 422,
          data: const {
            'detail': [
              {'msg': 'Field required'}
            ],
          },
        ),
      );

      expect(
        ApiError.messageFrom(error),
        'Field required',
      );
    });

    test('uses state error message directly', () {
      expect(
        ApiError.messageFrom(StateError('2FA code required')),
        '2FA code required',
      );
    });

    test('hides backend detail text when debug details are disabled', () {
      final error = DioException(
        requestOptions: requestOptions(),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions(),
          statusCode: 500,
          data: const {
            'error': {
              'code': 'internal_error',
              'message': 'traceback: RuntimeError boom',
            },
          },
        ),
      );

      expect(
        ApiError.messageFrom(
          error,
          includeDebugDetails: false,
        ),
        'Server error. Please try again later.',
      );
    });
  });
}
