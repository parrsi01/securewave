import 'package:dio/dio.dart';

import '../../services/api_client.dart';
import '../services/vpn_service.dart';

class ApiError {
  static String messageFrom(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is ApiClientException) {
      return _classifyApiClient(error, fallback: fallback);
    }
    if (error is VpnServiceException) {
      return _classifyVpn(error, fallback: fallback);
    }
    if (error is DioException) {
      return _classifyDio(error, fallback: fallback);
    }
    if (error is StateError) {
      return error.message;
    }
    return fallback;
  }

  static String _classifyApiClient(
    ApiClientException error, {
    required String fallback,
  }) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (error.code == 'kill_switch_active') {
      return 'Best-effort kill switch is blocking new app traffic until the tunnel reconnects or you disable it in Settings.';
    }
    if (error.code == 'auth_missing' ||
        error.code == '401' ||
        lower.contains('token') && lower.contains('expired') ||
        lower.contains('sign in again')) {
      return 'Your session expired. Sign in again to reconnect SecureWave.';
    }
    if (_isDeviceLimit(lower)) {
      return 'Device limit reached. Open Manage Devices in the portal, free a slot, then try again.';
    }
    if (lower.contains('dns')) {
      return 'DNS resolution failed. Retry diagnostics and verify tunnel DNS routing.';
    }
    if (lower.contains('route')) {
      return 'Routing validation failed. Check Diagnostics for route recovery guidance.';
    }
    if (lower.contains('timeout') ||
        lower.contains('connection refused') ||
        lower.contains('socketexception') ||
        lower.contains('backend')) {
      return 'Backend unreachable. Check connectivity and retry.';
    }
    return message.isEmpty ? fallback : message;
  }

  static String _classifyVpn(
    VpnServiceException error, {
    required String fallback,
  }) {
    final lower = error.message.toLowerCase();
    if (error.code == 'protocol_unavailable') {
      return 'Selected protocol is unavailable on this build. Switch to Auto or WireGuard.';
    }
    if (lower.contains('native tunnel did not report') ||
        lower.contains('tunnel') && lower.contains('failed')) {
      return 'Tunnel failed to come up cleanly. Retry or switch server.';
    }
    return error.message.isEmpty ? fallback : error.message;
  }

  static String _classifyDio(
    DioException error, {
    required String fallback,
  }) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail =
          data['detail']?.toString() ?? data['message']?.toString() ?? '';
      if (detail.isNotEmpty) {
        return _classifyApiClient(
          ApiClientException(
            error.response?.statusCode?.toString() ?? error.type.name,
            detail,
          ),
          fallback: fallback,
        );
      }
    }
    if (error.message != null && error.message!.isNotEmpty) {
      return _classifyApiClient(
        ApiClientException(error.type.name, error.message!),
        fallback: fallback,
      );
    }
    return fallback;
  }

  static bool _isDeviceLimit(String lower) {
    return (lower.contains('device') && lower.contains('limit')) ||
        lower.contains('too many devices') ||
        lower.contains('maximum devices') ||
        lower.contains('device slot');
  }
}
