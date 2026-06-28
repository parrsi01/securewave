import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  Dio failingDio(String baseUrl) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: Exception('boom'),
            ),
          );
        },
      ),
    );
    return dio;
  }

  test('ApiClient does not fall back to mock data when mock API is disabled',
      () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: false,
      simulateTunnel: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, dio: failingDio(config.apiBaseUrl));

    await expectLater(
      client.login(email: 'a@b.com', password: 'pw'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.register(email: 'a@b.com', password: 'pw'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchServers(forceRefresh: true),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchUserPlan(forceRefresh: true),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      client.fetchCurrentUser(),
      throwsA(isA<DioException>()),
    );
  });

  test('ApiClient returns mock data when mock API is enabled', () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: true,
      simulateTunnel: false,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, dio: failingDio(config.apiBaseUrl));

    final tokens =
        await client.login(email: 'alice@example.com', password: 'pw');
    expect(tokens.accessToken, contains('mock-token-'));

    final servers = await client.fetchServers(forceRefresh: true);
    expect(servers, isNotEmpty);

    final plan = await client.fetchUserPlan(forceRefresh: true);
    expect(plan.name, isNotEmpty);

    final account = await client.fetchCurrentUser();
    expect(account.email, isNotEmpty);
  });

  test('Presentation Mode keeps live API and simulates only the tunnel',
      () async {
    final config = AppConfig(
      apiBaseUrl: 'https://example.invalid',
      portalUrl: 'https://example.invalid',
      upgradeUrl: 'https://example.invalid',
      useMockApi: false,
      simulateTunnel: true,
      resetSessionOnBoot: false,
    );
    final client = ApiClient(config, dio: failingDio(config.apiBaseUrl));

    await expectLater(
      client.login(email: 'alice@example.com', password: 'pw'),
      throwsA(isA<DioException>()),
    );

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final vpn = container.read(vpnServiceProvider);
    expect(vpn.isNativeAvailable, isFalse);
    expect(
      await vpn.connect(protocol: VpnProtocol.wireGuard),
      VpnStatus.connected,
    );
    final stats = await vpn.getTrafficStats(VpnProtocol.wireGuard);
    expect(stats.countersAvailable, isFalse);
  });
}
