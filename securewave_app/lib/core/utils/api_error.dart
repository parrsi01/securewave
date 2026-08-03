import 'package:dio/dio.dart';

class ApiError {
  static String messageFrom(Object error,
      {String fallback = 'Something went wrong. Please try again.'}) {
    if (error is DioException) {
      final responseMessage = _responseMessage(error.response?.data);
      if (responseMessage != null) {
        return responseMessage;
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    if (error is StateError) {
      return error.message;
    }
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    if (message.startsWith('StateError: ')) {
      return message.substring('StateError: '.length);
    }
    return fallback;
  }

  static String? _responseMessage(Object? data) {
    if (data is! Map) return null;

    final nestedError = data['error'];
    if (nestedError is Map) {
      final message = _nonEmptyString(nestedError['message']);
      if (message != null) return message;
    } else {
      final message = _nonEmptyString(nestedError);
      if (message != null) return message;
    }

    final detail = _nonEmptyString(data['detail']);
    if (detail != null) return detail;
    return _nonEmptyString(data['message']);
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final message = value.trim();
    return message.isEmpty ? null : message;
  }
}
