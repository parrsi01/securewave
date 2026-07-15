import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/services/auth_session.dart';
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
          case 'deleteAll':
            store.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              store.entries
                  .where((entry) => entry.value != null)
                  .map((entry) => MapEntry(entry.key, entry.value!)),
            );
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

  test('AuthSession restores, persists, and clears tokens', () async {
    store['access_token'] = 'saved-token';

    final session = AuthSession();
    await session.ensureInitialized();

    expect(session.isInitialized, isTrue);
    expect(session.isAuthenticated, isTrue);
    expect(session.accessToken, 'saved-token');

    await session.clearSession();
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(store['access_token'], isNull);

    await session.setSession(accessToken: 'new-token');
    expect(session.isAuthenticated, isTrue);
    expect(session.accessToken, 'new-token');
    expect(store['access_token'], 'new-token');
  });

  test('an unauthorized backend response clears a restored session', () async {
    final session = AuthSession();
    await session.ensureInitialized();
    await session.setSession(accessToken: 'expired-token');

    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = _UnauthorizedAdapter();
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, session: session, dio: dio);

    await expectLater(client.fetchCurrentUser(), throwsA(isA<DioException>()));
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(store['access_token'], isNull);
  });

  test('UserPlan usage gauge handles zero-cap plans without NaN', () {
    const plan = UserPlan(
      name: 'Free',
      isPremium: false,
      dataCapGb: 0,
      usedGb: 1.2,
    );

    expect(plan.usagePercent, 0);
    expect(plan.remainingGb, 0);
  });
}

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('{"error":"unauthorized"}', 401);

  @override
  void close({bool force = false}) {}
}
