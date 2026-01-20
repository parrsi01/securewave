import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'auth_session.dart';
import 'secure_storage.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final authSession = ref.read(authSessionProvider);
  return ApiService(authSession);
});

class ApiService {
  ApiService(this._authSession) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  final AuthSession _authSession;
  final _storage = SecureStorage();
  late final Dio _dio;

  Future<Response<T>> get<T>(String path) async {
    return _request<T>(() => _dio.get(path));
  }

  Future<Response<T>> post<T>(String path, {dynamic data}) async {
    return _request<T>(() => _dio.post(path, data: data));
  }

  Future<Response<T>> patch<T>(String path, {dynamic data}) async {
    return _request<T>(() => _dio.patch(path, data: data));
  }

  Future<Response<T>> delete<T>(String path) async {
    return _request<T>(() => _dio.delete(path));
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() call) async {
    final accessToken = _authSession.accessToken ?? await _storage.getAccessToken();
    if (accessToken != null) {
      _dio.options.headers['Authorization'] = 'Bearer $accessToken';
    }

    try {
      return await call();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          return await call();
        }
      }
      rethrow;
    }
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _dio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      final data = response.data as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      if (accessToken == null) return false;
      await _authSession.setSession(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String?,
      );
      return true;
    } catch (_) {
      await _authSession.clearSession();
      return false;
    }
  }
}
