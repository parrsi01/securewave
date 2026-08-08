import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> store;
  var storageUnavailable = false;
  var failWrites = false;

  setUp(() {
    store = <String, String?>{};
    storageUnavailable = false;
    failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        if (storageUnavailable || (failWrites && methodCall.method == 'write')) {
          throw PlatformException(
            code: 'keyring_locked',
            message: 'keyring is locked; password must not be logged',
          );
        }
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

  test('keyring read failure keeps the app signed out and can retry later',
      () async {
    storageUnavailable = true;
    final session = AuthSession();

    await session.ensureInitialized();
    expect(session.isInitialized, isTrue);
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);

    storageUnavailable = false;
    await session.setSession(accessToken: 'retry-token');
    expect(session.isAuthenticated, isTrue);
    expect(store['access_token'], 'retry-token');
  });

  test('token storage failure does not create an in-memory authenticated state',
      () async {
    final session = AuthSession();
    await session.ensureInitialized();
    failWrites = true;

    await expectLater(
      session.setSession(accessToken: 'must-not-be-retained'),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(store['access_token'], isNull);
  });

  test('VPN state cleanup reports a locked keyring without exposing details',
      () async {
    storageUnavailable = true;

    await expectLater(
      SecureStorage().clearVpnRuntimeState(),
      throwsA(isA<SecureStorageUnavailableException>()),
    );
  });
}
