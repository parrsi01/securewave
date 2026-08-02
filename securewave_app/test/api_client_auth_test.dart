import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> store;

  setUp(() {
    store = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (methodCall.method) {
          case 'read':
            return key == null ? null : store[key];
          case 'write':
            if (key != null) store[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) store.remove(key);
            return null;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  test('retries one expired request after refreshing the access token',
      () async {
    final session = AuthSession();
    await session.setSession(
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://securewave.test'));
    final adapter = _AuthRefreshAdapter();
    dio.httpClientAdapter = adapter;
    final config = AppConfig(
      apiBaseUrl: 'https://securewave.test',
      portalUrl: 'https://securewave.test',
      upgradeUrl: 'https://securewave.test',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, session: session, dio: dio);

    final account = await client.fetchCurrentUser();

    expect(account.email, 'user@securewave.test');
    expect(adapter.protectedRequests, 2);
    expect(adapter.refreshRequests, 1);
    expect(session.accessToken, 'fresh-access');
    expect(await SecureStorage().getRefreshToken(), 'refresh-2');
  });

  test('failed refresh clears the session and does not retry forever',
      () async {
    final session = AuthSession();
    await session.setSession(
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://securewave.test'));
    final adapter = _AuthRefreshAdapter(failRefresh: true);
    dio.httpClientAdapter = adapter;
    final config = AppConfig(
      apiBaseUrl: 'https://securewave.test',
      portalUrl: 'https://securewave.test',
      upgradeUrl: 'https://securewave.test',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, session: session, dio: dio);

    await expectLater(client.fetchCurrentUser(), throwsA(isA<DioException>()));

    expect(adapter.protectedRequests, 1);
    expect(adapter.refreshRequests, 1);
    expect(session.isAuthenticated, isFalse);
    expect(await SecureStorage().getRefreshToken(), isNull);
  });
}

class _AuthRefreshAdapter implements HttpClientAdapter {
  _AuthRefreshAdapter({this.failRefresh = false});

  final bool failRefresh;
  int protectedRequests = 0;
  int refreshRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/auth/refresh') {
      refreshRequests += 1;
      if (failRefresh) {
        return ResponseBody.fromString(
          jsonEncode({'detail': 'invalid refresh token'}),
          401,
          headers: {
            'content-type': ['application/json']
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'access_token': 'fresh-access',
          'refresh_token': 'refresh-2',
        }),
        200,
        headers: {
          'content-type': ['application/json']
        },
      );
    }

    protectedRequests += 1;
    if (protectedRequests == 1) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'expired'}),
        401,
        headers: {
          'content-type': ['application/json']
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'id': 7,
        'email': 'user@securewave.test',
        'is_active': true,
        'email_verified': true,
        'has_2fa': false,
        'subscription_status': 'free',
      }),
      200,
      headers: {
        'content-type': ['application/json']
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
