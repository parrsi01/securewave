import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/utils/api_error.dart';

void main() {
  group('ApiError', () {
    test('uses the API detail message when supplied', () {
      final request = RequestOptions(path: '/auth/login');
      final error = DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 401,
          data: const {'detail': 'Invalid email or password.'},
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        ApiError.messageFrom(error),
        'Invalid email or password.',
      );
    });

    test('uses the API message field when detail is absent', () {
      final request = RequestOptions(path: '/auth/register');
      final error = DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 409,
          data: const {'message': 'An account already exists.'},
        ),
        type: DioExceptionType.badResponse,
      );

      expect(ApiError.messageFrom(error), 'An account already exists.');
    });

    test('preserves StateError messages and opaque-error fallback', () {
      expect(ApiError.messageFrom(StateError('Session unavailable.')),
          'Session unavailable.');
      expect(
        ApiError.messageFrom(
          Object(),
          fallback: 'Authentication could not be completed.',
        ),
        'Authentication could not be completed.',
      );
    });
  });
}
