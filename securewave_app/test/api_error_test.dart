import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/utils/api_error.dart';

void main() {
  test('surfaces the backend nested error message', () {
    final request = RequestOptions(path: '/auth/login');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 401,
        data: {
          'error': {
            'code': 'http_error',
            'message': 'Invalid credentials',
            'details': null,
          },
          'request_id': 'test-request-id',
        },
      ),
      type: DioExceptionType.badResponse,
    );

    expect(ApiError.messageFrom(error), 'Invalid credentials');
  });

  test('retains support for top-level backend error messages', () {
    final request = RequestOptions(path: '/auth/login');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 401,
        data: {'detail': 'Invalid credentials'},
      ),
      type: DioExceptionType.badResponse,
    );

    expect(ApiError.messageFrom(error), 'Invalid credentials');
  });
}
