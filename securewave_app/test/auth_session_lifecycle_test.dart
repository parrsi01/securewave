import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';

import 'state_machine/state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String jwtWithExp(int expSeconds) {
    String enc(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${enc(<String, Object>{'alg': 'none', 'typ': 'JWT'})}.'
        '${enc(<String, Object>{'sub': 'user-1', 'exp': expSeconds})}.'
        'signature';
  }

  test('restores authenticated session only for non-expired JWT', () async {
    final now = DateTime.utc(2026, 2, 22, 12);
    final futureToken = jwtWithExp(
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000);
    installSecureStorageMock(initial: <String, String?>{
      'access_token': futureToken,
    });

    final session = AuthSession(clock: () => now);
    await session.initializationComplete;

    expect(session.isAuthenticated, isTrue);
    expect(session.accessToken, futureToken);
  });

  test('expired JWT is purged during session restore', () async {
    final now = DateTime.utc(2026, 2, 22, 12);
    final expiredToken = jwtWithExp(
        now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000);
    final store = installSecureStorageMock(initial: <String, String?>{
      'access_token': expiredToken,
      'refresh_token': 'refresh',
      SecureStorage.vpnProfileConfigKey: '[Interface]\nAddress = 10.0.0.2/32\n',
      SecureStorage.vpnProfileExpiresAtKey: now.toIso8601String(),
      SecureStorage.vpnDeviceIdKey: '42',
    });

    final session = AuthSession(clock: () => now);
    await session.initializationComplete;

    expect(session.isAuthenticated, isFalse);
    expect(session.accessToken, isNull);
    expect(store['access_token'], isNull);
    expect(store['refresh_token'], isNull);
    expect(store[SecureStorage.vpnProfileConfigKey], isNull);
    expect(store[SecureStorage.vpnProfileExpiresAtKey], isNull);
    expect(store[SecureStorage.vpnDeviceIdKey], isNull);
  });

  test('reinstall-style invalid token is not reused and gets purged', () async {
    final store = installSecureStorageMock(initial: <String, String?>{
      'access_token': 'not-a-jwt',
      'refresh_token': 'stale-refresh',
    });

    final session = AuthSession(clock: () => DateTime.utc(2026, 2, 22, 12));
    await session.initializationComplete;

    expect(session.isAuthenticated, isFalse);
    expect(store['access_token'], isNull);
    expect(store['refresh_token'], isNull);
  });

  test('access token freshness gate blocks near-expiry JWT for auto-connect',
      () async {
    installSecureStorageMock();
    final now = DateTime.utc(2026, 2, 22, 12);
    final nearExpiryToken = jwtWithExp(
      now.add(const Duration(seconds: 45)).millisecondsSinceEpoch ~/ 1000,
    );
    final session = AuthSession(clock: () => now);
    await session.initializationComplete;
    await session.setSession(accessToken: nearExpiryToken);

    expect(
      session.hasFreshAccessToken(minValidity: const Duration(seconds: 60)),
      isFalse,
    );
    expect(
      session.accessTokenFreshnessIssue(
        minValidity: const Duration(seconds: 60),
      ),
      'expiring_or_expired_jwt',
    );
  });

  test('opaque access token is treated as fresh by client-side gate', () async {
    installSecureStorageMock();
    final session = AuthSession(clock: () => DateTime.utc(2026, 2, 22, 12));
    await session.initializationComplete;
    await session.setSession(accessToken: 'opaque-token');

    expect(session.hasFreshAccessToken(), isTrue);
    expect(session.accessTokenFreshnessIssue(), isNull);
  });

  test('clearSession removes persisted tokens and vpn session artifacts',
      () async {
    final now = DateTime.utc(2026, 2, 22, 12);
    final goodToken = jwtWithExp(
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000);
    final store = installSecureStorageMock(initial: <String, String?>{
      'access_token': goodToken,
      'refresh_token': 'refresh',
      SecureStorage.vpnProfileConfigKey: 'wgcfg',
      SecureStorage.vpnProfileExpiresAtKey: now.toIso8601String(),
      SecureStorage.vpnDeviceIdKey: '123',
    });

    final session = AuthSession(clock: () => now);
    await session.initializationComplete;
    expect(session.isAuthenticated, isTrue);

    await session.clearSession();

    expect(session.isAuthenticated, isFalse);
    expect(store['access_token'], isNull);
    expect(store['refresh_token'], isNull);
    expect(store[SecureStorage.vpnProfileConfigKey], isNull);
    expect(store[SecureStorage.vpnProfileExpiresAtKey], isNull);
    expect(store[SecureStorage.vpnDeviceIdKey], isNull);
  });
}
