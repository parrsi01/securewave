import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiError {
  static String messageFrom(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
    bool includeDebugDetails = !kReleaseMode,
  }) {
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
      if (includeDebugDetails) {
        if (data is Map<String, dynamic>) {
          if (data['detail'] is String) {
            return data['detail'] as String;
          }
          if (data['message'] is String) {
            return data['message'] as String;
          }
          final nestedError = data['error'];
          if (nestedError is Map<String, dynamic>) {
            if (nestedError['message'] is String) {
              return nestedError['message'] as String;
            }
            if (nestedError['detail'] is String) {
              return nestedError['detail'] as String;
            }
          }
        }
        if (data is Map && data['detail'] is List) {
          final detailList = data['detail'] as List;
          final firstMessage = detailList
              .whereType<Map>()
              .map((item) => item['msg']?.toString())
              .firstWhere(
                (value) => value != null && value.isNotEmpty,
                orElse: () => null,
              );
          if (firstMessage != null) {
            return firstMessage;
          }
        }
      } else {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          return 'Authentication failed. Please sign in again.';
        }
        if (status == 429) {
          return 'Too many requests. Please try again shortly.';
        }
        if (status != null && status >= 500) {
          return 'Server error. Please try again later.';
        }
      }
      if (includeDebugDetails &&
          error.message != null &&
          error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    if (includeDebugDetails && error is StateError && error.message.isNotEmpty) {
      return error.message;
    }
    return fallback;
  }
}
