import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';

import 'state_machine_test_harness.dart';

class _DeviceLimitStaleServerApiClient extends FakeApiClient {
  _DeviceLimitStaleServerApiClient({required super.config});

  final List<int?> requestedDeviceIds = <int?>[];
  final List<String?> requestedServerIds = <String?>[];

  @override
  Future<DeviceListResult> listDevices({CancelToken? cancelToken}) async {
    return const DeviceListResult(
      limit: 1,
      devices: <DeviceInfo>[
        DeviceInfo(
          id: 1,
          name: 'SecureWave Linux',
          deviceType: 'linux',
          ipAddress: '10.8.0.2',
          isActive: true,
          createdAt: '2026-03-19T00:00:00Z',
        ),
      ],
      total: 1,
      remaining: 0,
    );
  }

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
    requestedDeviceIds.add(deviceId);
    requestedServerIds.add(serverId);

    final requestOptions = RequestOptions(path: '/vpn/profile');
    if (requestedDeviceIds.length == 1) {
      throw DioException(
        requestOptions: requestOptions,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions,
          statusCode: 403,
          data: const <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'device_limit_reached',
              'message': 'Device limit reached.',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );
    }
    if (requestedDeviceIds.length == 2) {
      throw DioException(
        requestOptions: requestOptions,
        response: Response<Map<String, dynamic>>(
          requestOptions: requestOptions,
          statusCode: 404,
          data: const <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'server_not_found',
              'message': 'Server not found.',
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'device-limit recovery clears a stale selected server before final profile retry',
      () async {
    final store = installSecureStorageMock(
      initial: <String, String?>{
        SecureStorage.selectedServerKey: 'de-nue-1',
      },
    );
    final service = ControlledVpnService(
      connectDelay: const Duration(milliseconds: 25),
    );
    final api = _DeviceLimitStaleServerApiClient(config: testAppConfig());
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('de-nue-1');
    await settleStateMachine(turns: 8);

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );
    await settleStateMachine(turns: 20);

    expect(api.requestedDeviceIds, <int?>[null, 1, 1]);
    expect(api.requestedServerIds, <String?>['de-nue-1', 'de-nue-1', null]);
    expect(store[SecureStorage.selectedServerKey], isNull);
    expect(store[SecureStorage.vpnDeviceIdKey], '1');
    expect(container.read(vpnStateProvider).selectedServerId, 'us-chi');
    expect(service.connectCalls, 1);
  });
}
