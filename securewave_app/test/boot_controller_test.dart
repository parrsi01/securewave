import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/bootstrap/boot_controller.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> store;

  setUp(() {
    store = <String, String?>{};
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

  test('cold start with no token completes unauthenticated', () async {
    final session = AuthSession();
    final api = _BootApiClient(const []);
    final container = _container(api, session);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    await boot.ensureInitialized();

    expect(boot.state.status, BootStatus.ready);
    expect(session.isAuthenticated, isFalse);
    expect(session.isSessionValidated, isTrue);
    expect(api.currentUserCalls, 0);
  });

  test('valid stored token is validated once on cold start', () async {
    store['access_token'] = 'stored-token';
    final session = AuthSession();
    final api = _BootApiClient([() async => _account]);
    final container = _container(api, session);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    await boot.ensureInitialized();

    expect(boot.state.status, BootStatus.ready);
    expect(session.isAuthenticated, isTrue);
    expect(session.isSessionValidated, isTrue);
    expect(api.currentUserCalls, 1);
    expect(await SecureStorage().getAccountOwnerEmail(), _account.email);
  });

  test('temporary validation failure keeps token and exposes bounded retry',
      () async {
    store['access_token'] = 'stored-token';
    final session = AuthSession();
    final api = _BootApiClient([
      _connectionFailure,
      _connectionFailure,
      () async => _account,
    ]);
    final container = _container(api, session);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    await boot.ensureInitialized();

    expect(boot.state.status, BootStatus.offline);
    expect(session.isAuthenticated, isTrue);
    expect(await SecureStorage().getAccessToken(), 'stored-token');
    expect(api.currentUserCalls, 2);

    await boot.retry();

    expect(boot.state.status, BootStatus.ready);
    expect(session.isSessionValidated, isTrue);
    expect(api.currentUserCalls, 3);
  });

  test('explicit auth rejection clears local session and runtime state',
      () async {
    store['access_token'] = 'rejected-token';
    await SecureStorage().saveString(SecureStorage.selectedServerKey, 'old');
    await SecureStorage().saveInt(SecureStorage.vpnDeviceIdKey, 9);
    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKeyFor('wireguard'),
      '[Interface]\nDNS = 94.140.14.14\n',
    );
    final session = AuthSession();
    final api = _BootApiClient([_authFailure]);
    final container = _container(api, session);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    await boot.ensureInitialized();

    expect(boot.state.status, BootStatus.authRejected);
    expect(session.isAuthenticated, isFalse);
    expect(await SecureStorage().getAccessToken(), isNull);
    expect(await SecureStorage().getString(SecureStorage.selectedServerKey),
        isNull);
    expect(await SecureStorage().getInt(SecureStorage.vpnDeviceIdKey), isNull);
    expect(
      await SecureStorage()
          .getString(SecureStorage.vpnProfileConfigKeyFor('wireguard')),
      isNull,
    );
  });

  test('concurrent boot callers share one initialization request', () async {
    store['access_token'] = 'stored-token';
    final pending = Completer<UserAccount>();
    final session = AuthSession();
    final api = _BootApiClient([() => pending.future]);
    final container = _container(api, session);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    final first = boot.ensureInitialized();
    final second = boot.ensureInitialized();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(api.currentUserCalls, 1);

    pending.complete(_account);
    await first;
    expect(boot.state.status, BootStatus.ready);
  });

  test('reset-on-boot clears session-owned VPN runtime state', () async {
    store['access_token'] = 'stored-token';
    await SecureStorage().saveString(SecureStorage.selectedServerKey, 'old');
    await SecureStorage().saveInt(SecureStorage.vpnDeviceIdKey, 9);
    final session = AuthSession();
    final api = _BootApiClient(const []);
    final container = _container(api, session, resetSessionOnBoot: true);
    addTearDown(container.dispose);

    final boot = container.read(bootControllerProvider);
    await boot.ensureInitialized();

    expect(boot.state.status, BootStatus.ready);
    expect(session.isAuthenticated, isFalse);
    expect(await SecureStorage().getAccessToken(), isNull);
    expect(await SecureStorage().getString(SecureStorage.selectedServerKey),
        isNull);
    expect(await SecureStorage().getInt(SecureStorage.vpnDeviceIdKey), isNull);
    expect(await SecureStorage().getBool(SecureStorage.resetSessionDoneKey),
        isTrue);
  });
}

const _account = UserAccount(
  id: 1,
  email: 'person@example.test',
  isActive: true,
  emailVerified: true,
  has2fa: false,
  subscriptionStatus: 'free',
);

Future<UserAccount> _connectionFailure() async {
  throw DioException(
    requestOptions: RequestOptions(path: '/auth/me'),
    type: DioExceptionType.connectionError,
  );
}

Future<UserAccount> _authFailure() async {
  throw DioException(
    requestOptions: RequestOptions(path: '/auth/me'),
    response: Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/auth/me'),
      statusCode: 401,
    ),
  );
}

ProviderContainer _container(
  _BootApiClient api,
  AuthSession session, {
  bool resetSessionOnBoot = false,
}) {
  final config = AppConfig(
    apiBaseUrl: 'https://api.example.test',
    portalUrl: 'https://portal.example.test',
    upgradeUrl: 'https://upgrade.example.test',
    useMockApi: false,
    resetSessionOnBoot: resetSessionOnBoot,
  );
  return ProviderContainer(
    overrides: [
      authSessionProvider.overrideWith((ref) => session),
      appConfigProvider.overrideWith((ref) => config),
      apiClientProvider.overrideWithValue(api),
      vpnServiceProvider.overrideWithValue(
        MockVpnService(
            connectDelay: Duration.zero, disconnectDelay: Duration.zero),
      ),
      bootControllerProvider.overrideWith(
        (ref) => BootController(
          ref,
          configLoader: () async => config,
        ),
      ),
    ],
  );
}

class _BootApiClient extends ApiClient {
  _BootApiClient(this._responses)
      : super(
          AppConfig(
            apiBaseUrl: 'https://api.example.test',
            portalUrl: 'https://portal.example.test',
            upgradeUrl: 'https://upgrade.example.test',
            useMockApi: false,
            resetSessionOnBoot: false,
          ),
        );

  final List<Future<UserAccount> Function()> _responses;
  int currentUserCalls = 0;

  @override
  Future<UserAccount> fetchCurrentUser() async {
    currentUserCalls += 1;
    if (_responses.isEmpty) return _account;
    return _responses.removeAt(0)();
  }
}
