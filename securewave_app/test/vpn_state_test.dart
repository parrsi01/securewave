import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/models/user_plan.dart';
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

  test('auto-selected profile server is used for usage metering', () async {
    final service = _MeteredNativeVpnService();
    final api = _UsageTrackingApiClient(
      profileServerId: 'de-nue-1',
      profileProtocol: VpnProtocol.openVpn,
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.openVpn);
    notifier.selectServer(null);

    await notifier.connect();
    await Future<void>.delayed(Duration.zero);
    await notifier.disconnect();

    expect(api.connectedServerIds, <String?>['de-nue-1']);
    expect(api.usageServerIds, <String?>['de-nue-1']);
    expect(api.usageProtocols, <VpnProtocol?>[VpnProtocol.openVpn]);
    expect(api.rxBytes.single, greaterThan(0));
    expect(api.txBytes.single, greaterThan(0));
    final state = container.read(vpnStateProvider);
    expect(state.sessionRxBytes, api.rxBytes.single);
    expect(state.sessionTxBytes, api.txBytes.single);
    expect(state.sessionTotalBytes, api.rxBytes.single + api.txBytes.single);
    expect(state.sessionCountersAvailable, isTrue);
    expect(state.sessionCounterInterface, 'tun0');
  });

  test('traffic polling updates live speed and reports every second', () async {
    final service = _MeteredNativeVpnService();
    final api = _UsageTrackingApiClient(
      profileServerId: 'de-nue-1',
      profileProtocol: VpnProtocol.wireGuard,
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    var state = container.read(vpnStateProvider);
    expect(state.dataRateDown, greaterThan(0));
    expect(state.dataRateUp, greaterThan(0));
    expect(state.sessionTotalBytes, greaterThan(0));
    expect(api.rxBytes, isNotEmpty);
    expect(api.txBytes, isNotEmpty);

    await notifier.disconnect();
    state = container.read(vpnStateProvider);
    expect(state.dataRateDown, 0);
    expect(state.dataRateUp, 0);
  });

  test('missing tunnel counters show unavailable state without usage report',
      () async {
    final service = _UnavailableStatsVpnService();
    final api = _UsageTrackingApiClient(
      profileServerId: 'de-nue-1',
      profileProtocol: VpnProtocol.ikev2,
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.ikev2);
    await notifier.connect();
    await Future<void>.delayed(Duration.zero);
    await notifier.disconnect();

    final state = container.read(vpnStateProvider);
    expect(state.sessionCountersAvailable, isFalse);
    expect(state.sessionUsageReady, isFalse);
    expect(state.sessionTotalBytes, 0);
    expect(state.sessionCounterInterface, 'ipsec0');
    expect(state.sessionUsageUnavailableReason, contains('No readable'));
    expect(api.rxBytes, isEmpty);
    expect(api.txBytes, isEmpty);
  });

  test('VpnTrafficStats parses native counter availability metadata', () {
    final available = VpnTrafficStats.fromJson({
      'interface': 'sw-wg',
      'rx_bytes': '2048',
      'tx_bytes': 1024,
      'counters_available': true,
    });

    expect(available.rxBytes, 2048);
    expect(available.txBytes, 1024);
    expect(available.countersAvailable, isTrue);
    expect(available.interfaceName, 'sw-wg');

    final missing = VpnTrafficStats.fromJson({
      'interface': 'ipsec0',
      'rx_bytes': 0,
      'tx_bytes': 0,
      'counters_available': false,
      'unavailable_reason': 'No readable ipsec0 counters found.',
    });

    expect(missing.countersAvailable, isFalse);
    expect(missing.interfaceName, 'ipsec0');
    expect(missing.unavailableReason, contains('ipsec0'));
  });

  test('OpenVPN connect uses OpenVPN profile config without WireGuard fallback',
      () async {
    final service = _CapturingNativeVpnService();
    final api = _UsageTrackingApiClient(
      profileServerId: 'de-nue-1',
      profileProtocol: VpnProtocol.openVpn,
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.openVpn);

    await notifier.connect();

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(service.connectedProtocol, VpnProtocol.openVpn);
    expect(service.connectedConfig, startsWith('client\n'));
    expect(service.connectedConfig, contains('remote vpn.example 1194'));
    expect(service.connectedConfig, isNot(contains('[Interface]')));
  });

  test('IKEv2 connect uses IKEv2 profile config without protocol fallback',
      () async {
    final service = _CapturingNativeVpnService();
    final api = _UsageTrackingApiClient(
      profileServerId: 'de-nue-1',
      profileProtocol: VpnProtocol.ikev2,
    );

    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.selectProtocol(VpnProtocol.ikev2);

    await notifier.connect();

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(service.connectedProtocol, VpnProtocol.ikev2);
    expect(service.connectedConfig, contains('remote_addrs = vpn.example'));
    expect(service.connectedConfig, contains('eap_id = "ikev2-user"'));
    expect(service.connectedConfig, contains('secret = "ikev2-secret"'));
    expect(service.connectedConfig, isNot(contains('[Interface]')));
    expect(service.connectedConfig, isNot(startsWith('client\n')));
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
}

class _FailingVpnService implements VpnService {
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
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async =>
      VpnTrafficStats.zero;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}

class _NativeSuccessVpnService implements VpnService {
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
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async =>
      const VpnTrafficStats(rxBytes: 1024, txBytes: 256);

  @override
  VpnStatus getStatus() => _status;
}

class _MeteredNativeVpnService implements VpnService {
  VpnStatus _status = VpnStatus.disconnected;
  int _rxBytes = 1000;
  int _txBytes = 200;

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
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    _rxBytes += 4096;
    _txBytes += 1024;
    return VpnTrafficStats(
      rxBytes: _rxBytes,
      txBytes: _txBytes,
      interfaceName: 'tun0',
    );
  }

  @override
  VpnStatus getStatus() => _status;
}

class _UnavailableStatsVpnService implements VpnService {
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
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    return const VpnTrafficStats(
      rxBytes: 0,
      txBytes: 0,
      countersAvailable: false,
      interfaceName: 'ipsec0',
      unavailableReason: 'No readable ipsec0 rx_bytes/tx_bytes counters found.',
    );
  }

  @override
  VpnStatus getStatus() => _status;
}

class _CapturingNativeVpnService implements VpnService {
  VpnStatus _status = VpnStatus.disconnected;
  VpnProtocol? connectedProtocol;
  String? connectedConfig;

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
    connectedProtocol = protocol;
    connectedConfig = config;
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async =>
      VpnTrafficStats.zero;

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

class _UsageTrackingApiClient extends ApiClient {
  _UsageTrackingApiClient({
    required this.profileServerId,
    required this.profileProtocol,
  }) : super(AppConfig.defaults());

  final String profileServerId;
  final VpnProtocol profileProtocol;
  final connectedServerIds = <String?>[];
  final usageServerIds = <String?>[];
  final usageProtocols = <VpnProtocol?>[];
  final rxBytes = <int>[];
  final txBytes = <int>[];

  @override
  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
  }) async {
    return VpnProfile.fromJson({
      'device_id': 777,
      'device_name': deviceName,
      'device_type': deviceType,
      'protocol': vpnProtocolStorageValue(protocol),
      'server_id': profileServerId,
      'server_location': 'Nuremberg, Germany',
      'issued_at': DateTime.now().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'wireguard_config':
          '[Interface]\nPrivateKey = test\n[Peer]\nPublicKey = test\n',
      'openvpn_config': 'client\nremote vpn.example 1194\n',
      'ikev2_config': [
        'connections {',
        '  securewave {',
        '    version = 2',
        '    remote_addrs = vpn.example',
        '    local {',
        '      auth = eap-mschapv2',
        '      eap_id = "ikev2-user"',
        '    }',
        '    remote {',
        '      auth = pubkey',
        '      id = "vpn.example"',
        '    }',
        '  }',
        '}',
        'secrets {',
        '  eap-ikev2-user {',
        '    id = "ikev2-user"',
        '    secret = "ikev2-secret"',
        '  }',
        '}',
      ].join('\n'),
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
  }) async {
    connectedServerIds.add(serverId);
  }

  @override
  Future<void> notifyVpnDisconnected() async {}

  @override
  Future<UserPlan?> reportVpnUsage({
    int? deviceId,
    String? serverId,
    VpnProtocol? protocol,
    required int rxBytes,
    required int txBytes,
  }) async {
    usageServerIds.add(serverId);
    usageProtocols.add(protocol);
    this.rxBytes.add(rxBytes);
    this.txBytes.add(txBytes);
    return null;
  }
}
