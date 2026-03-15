import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

class _StaleDeviceRetryApiClient extends FakeApiClient {
  _StaleDeviceRetryApiClient({required super.config});

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
    if (deviceId != null && profileFetchCalls == 0) {
      profileFetchCalls += 1;
      throw DioException(
        requestOptions: RequestOptions(path: '/vpn/profile'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/vpn/profile'),
          statusCode: 404,
          data: const <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'device_not_found',
              'message': 'Device not found or revoked',
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

  test('stale cached device id is cleared and profile fetch retries once', () async {
    final store = installSecureStorageMock(
      initial: <String, String?>{
        SecureStorage.vpnDeviceIdKey: '321',
      },
    );
    final service = ControlledVpnService(
      connectDelay: const Duration(milliseconds: 25),
    );
    final api = _StaleDeviceRetryApiClient(config: testAppConfig());
    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await settleStateMachine(turns: 8);

    await notifier.connect();
    await waitForCondition(
      () => container.read(vpnStateProvider).status == VpnStatus.connected,
    );
    await settleStateMachine(turns: 20);

    expect(api.profileFetchCalls, 2);
    expect(service.connectCalls, 1);
    expect(container.read(vpnStateProvider).desiredOn, isTrue);
    expect(store[SecureStorage.vpnDeviceIdKey], '123');
  });
}
