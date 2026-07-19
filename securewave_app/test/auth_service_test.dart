import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/services/api_client.dart';
import 'package:securewave_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> values;
  late SecureStorage storage;
  late AuthSession session;
  late AuthService auth;

  setUp(() {
    values = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments is Map
            ? Map<String, dynamic>.from(call.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (call.method) {
          case 'read':
            return key == null ? null : values[key];
          case 'write':
            if (key != null) values[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) values.remove(key);
            return null;
          case 'deleteAll':
            values.clear();
            return null;
        }
        return null;
      },
    );
    storage = SecureStorage();
    session = AuthSession();
    auth = AuthService(_AuthApiClient(), session);
  });

  Future<void> seedVpnRuntime() async {
    await storage.saveString(SecureStorage.selectedServerKey, 'server-1');
    await storage.saveString(SecureStorage.vpnActiveServerIdKey, 'server-1');
    await storage.saveInt(SecureStorage.vpnDeviceIdKey, 7);
    await storage.saveString(
      SecureStorage.vpnProfileConfigKeyFor('wireguard'),
      '[Interface]\nDNS = 94.140.14.14',
    );
  }

  test('same-account login preserves durable VPN runtime state', () async {
    await seedVpnRuntime();
    await storage.saveAccountOwnerEmail('same@example.com');

    await auth.login(email: 'Same@Example.com', password: 'valid-password');

    expect(
        await storage.getString(SecureStorage.selectedServerKey), 'server-1');
    expect(await storage.getString(SecureStorage.vpnActiveServerIdKey),
        'server-1');
    expect(await storage.getInt(SecureStorage.vpnDeviceIdKey), 7);
    expect(await storage.getAccountOwnerEmail(), 'same@example.com');
    expect(session.isAuthenticated, isTrue);
  });

  test('account switch clears the previous VPN runtime state', () async {
    await seedVpnRuntime();
    await storage.saveAccountOwnerEmail('old@example.com');

    await auth.login(email: 'new@example.com', password: 'valid-password');

    expect(await storage.getString(SecureStorage.selectedServerKey), isNull);
    expect(await storage.getString(SecureStorage.vpnActiveServerIdKey), isNull);
    expect(await storage.getInt(SecureStorage.vpnDeviceIdKey), isNull);
    expect(await storage.getAccountOwnerEmail(), 'new@example.com');
  });

  test('verified debug reauthentication can preserve legacy runtime ownership',
      () async {
    await seedVpnRuntime();

    await auth.login(
      email: 'demo@example.com',
      password: 'valid-password',
      preserveVpnRuntime: true,
    );

    expect(
        await storage.getString(SecureStorage.selectedServerKey), 'server-1');
    expect(await storage.getAccountOwnerEmail(), 'demo@example.com');
  });

  test('logout clears credentials, ownership, and VPN runtime state', () async {
    await seedVpnRuntime();
    await storage.saveAccountOwnerEmail('same@example.com');
    await auth.login(email: 'same@example.com', password: 'valid-password');

    await auth.logout();

    expect(session.isAuthenticated, isFalse);
    expect(await storage.getAccountOwnerEmail(), isNull);
    expect(await storage.getString(SecureStorage.selectedServerKey), isNull);
  });
}

class _AuthApiClient extends ApiClient {
  _AuthApiClient()
      : super(AppConfig(
          apiBaseUrl: 'https://api.example.test',
          portalUrl: 'https://portal.example.test',
          upgradeUrl: 'https://upgrade.example.test',
          useMockApi: false,
          resetSessionOnBoot: false,
        ));

  @override
  Future<AuthTokens> login(
      {required String email, required String password}) async {
    return const AuthTokens(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
    );
  }

  @override
  Future<void> logout() async {}
}
