import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

import 'state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
  });

  test('test_async_backend_failure_during_connect', () async {
    final config = testAppConfig();
    final service = ControlledVpnService(nativeAvailable: true);
    final api = FakeApiClient(
      config: config,
      shouldFailProfile: true,
      profileError: DioException(
        requestOptions: RequestOptions(path: '/vpn/profile'),
        type: DioExceptionType.connectionError,
        error: 'backend_unreachable',
      ),
    );

    final container = buildVpnContainer(service: service, apiClient: api);
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();
    await settleStateMachine(turns: 20);

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorKind, VpnErrorKind.backendUnreachable);
    expect(service.connectCalls, 0);
  });
}
