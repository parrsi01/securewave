import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/services/api_client.dart';
import 'package:securewave_app/services/auth_service.dart';

class _Storage extends SecureStorage {
  String? value;
  int runtimeClearCalls = 0;

  @override
  Future<String?> getAccessToken() async => value;

  @override
  Future<void> saveToken(String accessToken) async {
    value = accessToken;
  }

  @override
  Future<void> clearToken() async {
    value = null;
  }

  @override
  Future<void> clearVpnRuntimeState() async {
    runtimeClearCalls += 1;
  }
}

class _FailingLogoutApi extends ApiClient {
  _FailingLogoutApi(AuthSession session)
      : super(
          const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: false,
          ),
          session: session,
        );

  @override
  Future<void> logout() => Future<void>.error(
        StateError('Control plane unavailable.'),
      );
}

void main() {
  test('authenticated session restores and clears local state', () async {
    final storage = _Storage()..value = 'opaque-example.test-session';
    final session = AuthSession(storage: storage);
    await session.ensureInitialized();

    expect(session.isAuthenticated, isTrue);
    await session.clearSession();
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(storage.value, isNull);
  });

  test('logout clears session and VPN runtime after API failure', () async {
    final storage = _Storage()..value = 'opaque-example.test-session';
    final session = AuthSession(storage: storage);
    await session.ensureInitialized();
    final service = AuthService(
      _FailingLogoutApi(session),
      session,
      storage,
    );

    await expectLater(service.logout(), throwsStateError);
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(storage.runtimeClearCalls, 1);
  });
}
