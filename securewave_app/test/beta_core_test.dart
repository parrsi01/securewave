import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/services/api_client.dart';

class MemorySecureStorage extends SecureStorage {
  String? token;
  bool failReads = false;

  @override
  Future<String?> getAccessToken() async {
    if (failReads) throw StateError('storage unavailable');
    return token;
  }

  @override
  Future<void> saveToken(String accessToken) async => token = accessToken;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<void> clearVpnRuntimeState() async {}
}

void main() {
  test('release configuration has an explicit non-local API URL', () {
    final config = AppConfig.defaults();
    expect(config.apiBaseUrl, startsWith('https://'));
    expect(config.apiBaseUrl, isNot(contains('localhost')));
    expect(config.demoMode, isFalse);
  });

  test('profile parser keeps only the WireGuard beta contract', () {
    final profile = VpnProfile.fromJson({
      'device_id': 7,
      'device_name': 'Linux',
      'device_type': 'linux',
      'server_id': 'hetzner-one',
      'server_location': 'SecureWave Beta',
      'wireguard_config': '[Interface]\nPrivateKey = redacted',
    });
    expect(profile.deviceId, 7);
    expect(profile.wireguardConfig, contains('[Interface]'));
    expect(profile.serverId, 'hetzner-one');
  });

  test('demo service is deterministic and never needs a network', () async {
    final service = DemoVpnService();
    expect(service.isAvailable, isTrue);
    expect(await service.connect(config: '# demo'), VpnStatus.connected);
    final first = await service.getTrafficStats();
    final second = await service.getTrafficStats();
    expect(first.rxBytes, 8192);
    expect(first.txBytes, 4096);
    expect(second.rxBytes, 16384);
    expect(second.txBytes, 8192);
    expect(await service.disconnect(), VpnStatus.disconnected);
    expect(await service.connect(config: '# demo'), VpnStatus.connected);
    expect((await service.refreshRuntimeStatus()).status, VpnStatus.connected);
    final reconnected = await service.getTrafficStats();
    expect(reconnected.rxBytes, 8192);
    expect(reconnected.txBytes, 4096);
    expect(await service.disconnect(), VpnStatus.disconnected);
  });

  test('auth session survives restart and fails closed on storage errors',
      () async {
    final storage = MemorySecureStorage();
    final first = AuthSession(storage: storage);
    await first.ensureInitialized();
    await first.setSession(accessToken: 'persisted-access-token');

    final restarted = AuthSession(storage: storage);
    await restarted.ensureInitialized();
    expect(restarted.isAuthenticated, isTrue);
    expect(restarted.accessToken, 'persisted-access-token');

    await restarted.clearSession();
    expect(storage.token, isNull);

    storage.failReads = true;
    final failedRestore = AuthSession(storage: storage);
    await failedRestore.ensureInitialized();
    expect(failedRestore.isAuthenticated, isFalse);
    expect(failedRestore.accessToken, isNull);
  });

  test('demo API boundary performs no HTTP requests', () async {
    final storage = MemorySecureStorage();
    final session = AuthSession(storage: storage);
    await session.ensureInitialized();
    final dio =
        Dio(BaseOptions(baseUrl: 'https://network-must-not-run.invalid/api'));
    var requested = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requested = true;
      handler.reject(DioException(
        requestOptions: options,
        message: 'Demo attempted a network request.',
      ));
    }));
    final api = ApiClient(
      const AppConfig(
        apiBaseUrl: 'https://network-must-not-run.invalid/api',
        demoMode: true,
      ),
      session: session,
      dio: dio,
    );

    final registered = await api.register(
      email: 'reviewer@example.test',
      password: 'Secure123',
    );
    final loggedIn = await api.login(
      email: 'reviewer@example.test',
      password: 'Secure123',
    );
    final user = await api.fetchCurrentUser();
    final target = await api.fetchTarget();
    final profile = await api.fetchVpnProfile(
      deviceName: 'Demo Linux',
      deviceType: 'linux',
    );
    await api.logout();

    expect(registered.accessToken, 'demo-session-reviewer@example.test');
    expect(loggedIn.accessToken, registered.accessToken);
    expect(user.email, 'demo@securewave.local');
    expect(target.location, 'Simulated target');
    expect(profile.wireguardConfig, contains('DEMO ONLY'));
    expect(requested, isFalse);
  });
}
