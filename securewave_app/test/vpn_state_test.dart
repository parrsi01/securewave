import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub flutter_secure_storage platform channel (unavailable in test harness)
    final store = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
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
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  });

  test('VpnStateNotifier transitions through connect and disconnect', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');

    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('VpnStateNotifier allows auto-select server', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('de-nue-1');
    expect(container.read(vpnStateProvider).selectedServerId, 'de-nue-1');
    notifier.selectServer(null);
    expect(container.read(vpnStateProvider).selectedServerId, isNull);

    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
  });

  test(
      'VpnStateNotifier cannot remain connected when kill switch hooks present and network drops',
      () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    expect(container.read(vpnStateProvider).status, VpnStatus.error);
  });

  test('VpnStateNotifier does not mark connected when native connect fails',
      () async {
    final service = _FailingVpnService();
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.lastTunnelStartOk, isFalse);
  });

  test('stale stored VPN device id is cleared and profile fetch retries',
      () async {
    final service = _NativeSuccessVpnService();
    final api = _ReferenceRecoveryApiClient(
        failFirstDetail: 'Device not found or revoked');
    await SecureStorage().saveInt(SecureStorage.vpnDeviceIdKey, 999);

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();

    expect(api.deviceIds, <int?>[999, null]);
    expect(await SecureStorage().getInt(SecureStorage.vpnDeviceIdKey), 321);
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(container.read(vpnStateProvider).lastProfileFetchOk, isTrue);
  });

  test('stale selected server is cleared and profile fetch retries', () async {
    final service = _NativeSuccessVpnService();
    final api =
        _ReferenceRecoveryApiClient(failFirstDetail: 'Server not found');

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('old-provider-server');
    await notifier.connect();

    expect(api.serverIds, <String?>['old-provider-server', null]);
    expect(container.read(vpnStateProvider).selectedServerId, isNull);
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
  });

  test('device limit profile error remains precise', () async {
    final service = _NativeSuccessVpnService();
    final api = _AlwaysFailingProfileApiClient(
      statusCode: 403,
      body: {
        'error': {
          'code': 'device_limit_reached',
          'message':
              'Device limit reached (1). Upgrade your plan or revoke an existing device.',
        },
      },
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.errorKind, VpnErrorKind.deviceLimit);
    expect(state.errorMessage, contains('Device limit reached'));
  });

  test(
      'usage meter accumulates deltas, ignores counter reset, and stops cleanly',
      () async {
    final service = _CounterVpnService([
      const VpnTrafficStats(rxBytes: 100, txBytes: 200),
      const VpnTrafficStats(rxBytes: 160, txBytes: 260),
      const VpnTrafficStats(rxBytes: 20, txBytes: 30),
    ]);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await Future<void>.delayed(const Duration(milliseconds: 1150));

    var state = container.read(vpnStateProvider);
    expect(state.sessionCountersAvailable, isTrue);
    expect(state.sessionRxBytes, 60);
    expect(state.sessionTxBytes, 60);
    expect(state.dataRateDown, greaterThan(0));

    await Future<void>.delayed(const Duration(milliseconds: 1050));
    state = container.read(vpnStateProvider);
    expect(state.sessionRxBytes, 60);
    expect(state.sessionTxBytes, 60);

    await notifier.disconnect();
    final callsAfterDisconnect = service.trafficCalls;
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(service.trafficCalls, callsAfterDisconnect);
    expect(container.read(vpnStateProvider).dataRateDown, 0);
  });

  test('usage meter prevents overlapping counter polls', () async {
    final service = _CounterVpnService(
      const [VpnTrafficStats(rxBytes: 100, txBytes: 200)],
      statsDelay: const Duration(milliseconds: 1300),
    );
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(service.trafficCalls, 1);
  });
}

class _CounterVpnService extends VpnService {
  _CounterVpnService(this.samples, {this.statsDelay = Duration.zero});

  final List<VpnTrafficStats> samples;
  final Duration statsDelay;
  VpnStatus _status = VpnStatus.disconnected;
  int trafficCalls = 0;

  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;

  @override
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    trafficCalls += 1;
    if (statsDelay > Duration.zero) await Future<void>.delayed(statsDelay);
    final index = trafficCalls - 1;
    return samples[index < samples.length ? index : samples.length - 1];
  }
}

class _FailingVpnService extends VpnService {
  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({required VpnProtocol protocol, String? config}) {
    throw VpnServiceException('vpn_connect_failed', 'native connect failed');
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}

class _NativeSuccessVpnService extends VpnService {
  VpnStatus _status = VpnStatus.disconnected;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    if (config == null || config.trim().isEmpty) {
      throw VpnServiceException('invalid_config', 'missing config');
    }
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class _ReferenceRecoveryApiClient extends ApiClient {
  _ReferenceRecoveryApiClient({required this.failFirstDetail})
      : super(AppConfig.defaults());

  final String failFirstDetail;
  final deviceIds = <int?>[];
  final serverIds = <String?>[];
  int _calls = 0;

  @override
  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
  }) async {
    _calls += 1;
    deviceIds.add(deviceId);
    serverIds.add(serverId);
    if (_calls == 1) {
      throw DioException(
        requestOptions: RequestOptions(path: '/vpn/profile'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/vpn/profile'),
          statusCode: 404,
          data: {'detail': failFirstDetail},
        ),
      );
    }
    return VpnProfile.fromJson({
      'device_id': 321,
      'device_name': deviceName,
      'device_type': deviceType,
      'protocol': protocol == VpnProtocol.openVpn ? 'openvpn' : 'wireguard',
      'server_id': 'de-nue-1',
      'server_location': 'Nuremberg, Germany',
      'issued_at': DateTime.now().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'wireguard_config':
          '[Interface]\nPrivateKey = test\n[Peer]\nPublicKey = test\n',
      'openvpn_config': 'client\n',
      'ikev2_config': '',
      'dns': {
        'servers': ['94.140.14.14'],
        'enforcement': 'config',
      },
      'kill_switch': {
        'mode': 'enabled',
        'enforcement': 'best effort',
      },
      'peer_registered': true,
      'registration_status': 'test',
    });
  }

  @override
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {}

  @override
  Future<void> notifyVpnDisconnected() async {}
}

class _AlwaysFailingProfileApiClient extends ApiClient {
  _AlwaysFailingProfileApiClient({
    required this.statusCode,
    required this.body,
  }) : super(AppConfig.defaults());

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/vpn/profile'),
      response: Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/vpn/profile'),
        statusCode: statusCode,
        data: body,
      ),
    );
  }
}
