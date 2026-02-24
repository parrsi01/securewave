import 'package:dio/dio.dart';

class ApiError {
  static String messageFrom(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
    if (error is DioException) {
      // Network-level failures — classify before inspecting the response body.
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'The server is taking too long to respond. Check your network and try again.';
        case DioExceptionType.connectionError:
          return 'Cannot reach the server. Make sure you are connected and the backend is running.';
        default:
          break;
      }

      // HTTP error — prefer the API's own detail/message fields.
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] is String) {
        return data['detail'] as String;
      }
      if (data is Map<String, dynamic> && data['message'] is String) {
        return data['message'] as String;
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return fallback;
  }
}
