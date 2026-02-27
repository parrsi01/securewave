import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';

import 'state_machine_test_harness.dart';

class _FailoverApiClient extends FakeApiClient {
  _FailoverApiClient({
    required super.config,
    required this.resolvedRegionId,
    this.failFirstProfileAsRegionDown = false,
  });

  final String resolvedRegionId;
  final bool failFirstProfileAsRegionDown;

  int resolveCalls = 0;
  int _profileCallNumber = 0;
  final List<String?> requestedServerIds = <String?>[];
  int get attemptedProfileFetchCalls => _profileCallNumber;

  @override
  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
    CancelToken? cancelToken,
  }) async {
    requestedServerIds.add(serverId);
    _profileCallNumber += 1;
    if (failFirstProfileAsRegionDown && _profileCallNumber == 1) {
      final requestOptions = RequestOptions(path: '/vpn/profile');
      throw DioException(
        requestOptions: requestOptions,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions,
          statusCode: 409,
          data: const <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'region_down',
              'message': 'Selected region is offline.',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return super.fetchVpnProfile(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
      protocol: protocol,
      serverId: serverId,
      forceRotateKeys: forceRotateKeys,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<VpnResolvedRegion> resolveRegion({
    required VpnProtocol protocol,
    required String deviceType,
    String? preferredRegion,
    CancelToken? cancelToken,
  }) async {
    resolveCalls += 1;
    return VpnResolvedRegion(
      selectedRegionId: resolvedRegionId,
      reason: 'failover_primary_down',
      protocol: vpnProtocolStorageValue(protocol),
      deviceType: deviceType,
      preferredRegion: preferredRegion,
      userGeoGroup: 'north_america',
      cacheHit: false,
    );
  }
}

ProviderContainer _buildContainer({
  required ControlledVpnService service,
  required ApiClient apiClient,
  required List<ServerRegion> servers,
}) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWith((ref) => testAppConfig()),
      vpnServiceProvider.overrideWithValue(service),
      apiClientProvider.overrideWithValue(apiClient),
      serversProvider.overrideWith((ref) async => servers),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('auto-failover resolves a healthy region when selected region is down',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = _FailoverApiClient(
      config: config,
      resolvedRegionId: 'up-region',
    );
    final container = _buildContainer(
      service: service,
      apiClient: api,
      servers: const <ServerRegion>[
        ServerRegion(
          id: 'down-region',
          name: 'Primary Region',
          regionHealthStatus: 'down',
        ),
        ServerRegion(
          id: 'up-region',
          name: 'Fallback Region',
          regionHealthStatus: 'up',
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serversProvider.future);
    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('down-region');
    await notifier.connect();
    await settleStateMachine(turns: 30);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.selectedServerId, 'up-region');
    expect(state.failoverActive, isTrue);
    expect(state.failoverRegionId, 'up-region');
    expect(service.connectCalls, 1);
    expect(api.resolveCalls, 1);
    expect(api.profileFetchCalls, 1);
  });

  test(
      'region_down profile error retries once via failover without duplicate runtime connect attempts',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = _FailoverApiClient(
      config: config,
      resolvedRegionId: 'fallback-up',
      failFirstProfileAsRegionDown: true,
    );
    final container = _buildContainer(
      service: service,
      apiClient: api,
      servers: const <ServerRegion>[
        ServerRegion(
          id: 'primary-up',
          name: 'Primary Region',
          regionHealthStatus: 'up',
        ),
        ServerRegion(
          id: 'fallback-up',
          name: 'Fallback Region',
          regionHealthStatus: 'up',
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serversProvider.future);
    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('primary-up');
    await notifier.connect();
    await settleStateMachine(turns: 40);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.selectedServerId, 'fallback-up');
    expect(state.failoverActive, isTrue);
    expect(api.resolveCalls, 1);
    expect(api.attemptedProfileFetchCalls, 2);
    expect(api.requestedServerIds, <String?>['primary-up', 'fallback-up']);
    expect(service.connectCalls, 1);
    expect(
      notifier.debugTransitionHistory
          .any((entry) => entry.to == VpnStatus.error),
      isFalse,
    );
  });

  test('fails hard and does not connect when all regions are down', () async {
    final AppConfig config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = _FailoverApiClient(
      config: config,
      resolvedRegionId: 'unused-fallback',
    );
    final container = _buildContainer(
      service: service,
      apiClient: api,
      servers: const <ServerRegion>[
        ServerRegion(
          id: 'down-1',
          name: 'Region 1',
          regionHealthStatus: 'down',
        ),
        ServerRegion(
          id: 'down-2',
          name: 'Region 2',
          regionHealthStatus: 'down',
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serversProvider.future);
    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('down-1');
    await notifier.connect();
    await settleStateMachine(turns: 30);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorKind, VpnErrorKind.protocolUnavailable);
    expect(state.errorMessage, contains('No servers available'));
    expect(service.connectCalls, 0);
    expect(api.resolveCalls, 0);
  });

  test('manual region override is preserved when selected region is healthy',
      () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = _FailoverApiClient(
      config: config,
      resolvedRegionId: 'auto-fallback',
    );
    final container = _buildContainer(
      service: service,
      apiClient: api,
      servers: const <ServerRegion>[
        ServerRegion(
          id: 'manual-up',
          name: 'Manual Region',
          regionHealthStatus: 'up',
        ),
        ServerRegion(
          id: 'auto-fallback',
          name: 'Fallback Region',
          regionHealthStatus: 'up',
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serversProvider.future);
    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('manual-up');
    await notifier.connect();
    await settleStateMachine(turns: 30);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
    expect(state.selectedServerId, 'manual-up');
    expect(state.failoverActive, isFalse);
    expect(api.resolveCalls, 0);
    expect(api.requestedServerIds, isNotEmpty);
    expect(api.requestedServerIds.first, 'manual-up');
  });
}
