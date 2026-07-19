import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/protocol_availability.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';

Map<String, dynamic> _threatDnsFixture() => {
      'servers': ['94.140.14.14'],
      'ad_malware_blocking': 'on',
      'enforcement': 'config',
      'blocked_categories': ['ads', 'trackers', 'phishing', 'malware'],
      'policy_engine': 'marl_xgboost_risk_assessment',
    };

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
    await notifier.ensureInitialized();
    notifier.selectServer('us-chi');

    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('disconnect stays available while connected bookkeeping is pending',
      () async {
    final service = MockVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final api = _PendingConnectNotificationApiClient();
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(() {
      api.release();
      container.dispose();
    });

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    await notifier.connect().timeout(const Duration(seconds: 1));

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(container.read(vpnStateProvider).isBusy, isFalse);
    expect(api.notificationStarted, isTrue);

    await notifier.disconnect().timeout(const Duration(seconds: 1));
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('VPN availability refresh disables itself until both providers settle',
      () async {
    final servers = Completer<List<ServerRegion>>();
    final availability = Completer<Map<VpnProtocol, ProtocolAvailability>>();
    final api = _RefreshTrackingApiClient();
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(MockVpnService()),
        apiClientProvider.overrideWithValue(api),
        serversProvider.overrideWith((ref) => servers.future),
        protocolAvailabilityProvider.overrideWith((ref) => availability.future),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    final refresh = notifier.refreshConnectivity();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(vpnStateProvider).isBusy, isTrue);
    expect(container.read(vpnStateProvider).isRefreshing, isTrue);

    servers.complete(const []);
    availability.complete(const {});
    await refresh;

    expect(container.read(vpnStateProvider).isBusy, isFalse);
    expect(container.read(vpnStateProvider).isRefreshing, isFalse);
    expect(api.forceRefreshCalls, 1);
    expect(api.deviceTypes, ['linux']);
  });

  test('VpnStateNotifier exposes one deterministic initialization future',
      () async {
    final service = _InitializationTrackingVpnService();
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    final first = notifier.ensureInitialized();
    final second = notifier.ensureInitialized();
    expect(identical(first, second), isTrue);

    service.releaseAvailabilityChecks();
    await first;
    expect(service.refreshedProtocols, VpnProtocol.values);
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

  test('OpenVPN rolls back when authenticated egress proof fails', () async {
    final service = _NativeSuccessVpnService();
    final api = _CredentialedEgressApiClient(
      protocol: VpnProtocol.openVpn,
      egressVerified: false,
    );
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    await notifier.selectProtocol(VpnProtocol.openVpn);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(api.baselineCalls, 1);
    expect(api.verifyCalls, 1);
    expect(service.disconnectCalls, 1);
    expect(state.status, VpnStatus.error);
    expect(state.lastTunnelStartOk, isFalse);
  });

  test('IKEv2 rolls back when authenticated egress proof fails', () async {
    final service = _NativeSuccessVpnService();
    final api = _CredentialedEgressApiClient(
      protocol: VpnProtocol.ikev2,
      egressVerified: false,
    );
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    await notifier.selectProtocol(VpnProtocol.ikev2);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(api.baselineCalls, 1);
    expect(api.verifyCalls, 1);
    expect(service.disconnectCalls, 1);
    expect(state.status, VpnStatus.error);
    expect(state.lastTunnelStartOk, isFalse);
  });

  test('IKEv2 runtime restoration disconnects without a fresh egress baseline',
      () async {
    final service = _RestoredCredentialedVpnService(VpnProtocol.ikev2);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).ensureInitialized();

    expect(service.disconnectCalls, 1);
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
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

  test('usage reporting sends deltas serially and retries without double count',
      () async {
    final service = _CounterVpnService([
      const VpnTrafficStats(rxBytes: 100, txBytes: 200),
      const VpnTrafficStats(rxBytes: 160, txBytes: 260),
      const VpnTrafficStats(rxBytes: 190, txBytes: 280),
    ], nativeAvailable: true);
    final api = _UsageTrackingApiClient(failFirstReport: true);
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    expect(container.read(vpnStateProvider).threatProtectionActive, isTrue);
    expect(
      container.read(vpnStateProvider).threatProtectionCategories,
      containsAll(['ads', 'trackers', 'phishing', 'malware']),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2150));
    await notifier.disconnect();

    expect(api.reportAttempts, [
      (sequence: 1, sent: 60, received: 60),
      (sequence: 1, sent: 80, received: 90),
    ]);
    expect(api.finalizedSessionIds, [42]);
    expect(container.read(vpnStateProvider).threatProtectionActive, isFalse);
  });

  test('native connect fails closed without proven DNS threat protection',
      () async {
    final service = _CounterVpnService(
      const [VpnTrafficStats(rxBytes: 0, txBytes: 0)],
      nativeAvailable: true,
    );
    final api = _UsageTrackingApiClient(
      failFirstReport: false,
      includeThreatProtection: false,
    );
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vpnStateProvider.notifier).connect();

    expect(container.read(vpnStateProvider).status, VpnStatus.error);
    expect(container.read(vpnStateProvider).threatProtectionActive, isFalse);
    expect(container.read(vpnStateProvider).errorMessage,
        contains('threat protection'));
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
  _CounterVpnService(
    this.samples, {
    this.statsDelay = Duration.zero,
    this.nativeAvailable = false,
  });

  final List<VpnTrafficStats> samples;
  final Duration statsDelay;
  final bool nativeAvailable;
  VpnStatus _status = VpnStatus.disconnected;
  int trafficCalls = 0;

  @override
  bool get isNativeAvailable => nativeAvailable;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async =>
      true;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async {
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

class _RefreshTrackingApiClient extends ApiClient {
  _RefreshTrackingApiClient() : super(AppConfig.defaults());

  int forceRefreshCalls = 0;
  final deviceTypes = <String?>[];

  @override
  Future<List<ServerRegion>> fetchServers({
    bool forceRefresh = false,
    String? deviceType,
  }) async {
    if (forceRefresh) forceRefreshCalls += 1;
    deviceTypes.add(deviceType);
    return const [];
  }
}

class _PendingConnectNotificationApiClient extends ApiClient {
  _PendingConnectNotificationApiClient() : super(AppConfig.defaults());

  final _pending = Completer<void>();
  bool notificationStarted = false;

  void release() {
    if (!_pending.isCompleted) _pending.complete();
  }

  @override
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {
    notificationStarted = true;
    await _pending.future;
  }

  @override
  Future<void> notifyVpnDisconnected() async {}
}

class _UsageTrackingApiClient extends ApiClient {
  _UsageTrackingApiClient({
    required this.failFirstReport,
    this.includeThreatProtection = true,
  }) : super(AppConfig(
          apiBaseUrl: 'https://api.example.test',
          portalUrl: 'https://portal.example.test',
          upgradeUrl: 'https://upgrade.example.test',
          useMockApi: true,
          resetSessionOnBoot: false,
        ));

  final bool failFirstReport;
  final bool includeThreatProtection;
  final List<({int sequence, int sent, int received})> reportAttempts = [];
  final List<int> finalizedSessionIds = [];

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
      'device_id': 7,
      'server_id': serverId ?? 'metering-server',
      'protocol': 'wireguard',
      'wireguard_config': '[Interface]\nPrivateKey = test\nDNS = 94.140.14.14',
      if (includeThreatProtection) 'dns': _threatDnsFixture(),
      'peer_registered': true,
    });
  }

  @override
  Future<int?> startUsageSession({
    required int deviceId,
    required String serverId,
    required VpnProtocol protocol,
    required String idempotencyKey,
  }) async =>
      42;

  @override
  Future<void> reportUsage({
    required int sessionId,
    required int sequence,
    required int bytesSent,
    required int bytesReceived,
    required String idempotencyKey,
  }) async {
    reportAttempts.add((
      sequence: sequence,
      sent: bytesSent,
      received: bytesReceived,
    ));
    if (failFirstReport && reportAttempts.length == 1) {
      throw StateError('transient metering failure');
    }
  }

  @override
  Future<void> finalizeUsageSession({
    required int sessionId,
    required String idempotencyKey,
    String reason = 'client_disconnect',
  }) async {
    finalizedSessionIds.add(sessionId);
  }
}

class _InitializationTrackingVpnService extends VpnService {
  final _availabilityGate = Completer<void>();
  final refreshedProtocols = <VpnProtocol>[];

  void releaseAvailabilityChecks() => _availabilityGate.complete();

  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => false;

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async {
    await _availabilityGate.future;
    refreshedProtocols.add(protocol);
    return false;
  }

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) =>
      'Helper probe unavailable.';

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async =>
      VpnStatus.disconnected;

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}

class _FailingVpnService extends VpnService {
  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) {
    throw VpnServiceException('vpn_connect_failed', 'native connect failed');
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}

class _NativeSuccessVpnService extends VpnService {
  VpnStatus _status = VpnStatus.disconnected;
  int disconnectCalls = 0;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async {
    if (config == null || config.trim().isEmpty) {
      throw VpnServiceException('invalid_config', 'missing config');
    }
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    disconnectCalls += 1;
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class _RestoredCredentialedVpnService extends _NativeSuccessVpnService {
  _RestoredCredentialedVpnService(this.restoredProtocol);

  final VpnProtocol restoredProtocol;

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async => VpnRuntimeStatus(
        status: VpnStatus.connected,
        protocol: restoredProtocol,
      );
}

class _ReferenceRecoveryApiClient extends ApiClient {
  _ReferenceRecoveryApiClient({required this.failFirstDetail})
      : super(AppConfig.defaults());

  final String failFirstDetail;
  final deviceIds = <int?>[];
  final serverIds = <String?>[];
  int _calls = 0;

  @override
  Future<Map<VpnProtocol, ProtocolAvailability>> fetchProtocolAvailability({
    String? deviceType,
  }) async =>
      _allProtocolsAvailable();

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
          '[Interface]\nPrivateKey = test\nDNS = 94.140.14.14\n[Peer]\nPublicKey = test\n',
      'openvpn_config': 'client\ndhcp-option DNS 94.140.14.14\n',
      'ikev2_config': '',
      'dns': _threatDnsFixture(),
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
  Future<Map<VpnProtocol, ProtocolAvailability>> fetchProtocolAvailability({
    String? deviceType,
  }) async =>
      _allProtocolsAvailable();

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

class _CredentialedEgressApiClient extends ApiClient {
  _CredentialedEgressApiClient({
    required this.protocol,
    required this.egressVerified,
  }) : super(AppConfig.defaults());

  final VpnProtocol protocol;
  final bool egressVerified;
  int baselineCalls = 0;
  int verifyCalls = 0;

  @override
  Future<Map<VpnProtocol, ProtocolAvailability>> fetchProtocolAvailability({
    String? deviceType,
  }) async =>
      _allProtocolsAvailable();

  @override
  Future<String> captureVpnEgressBaseline() async {
    baselineCalls += 1;
    return 'a' * 64;
  }

  @override
  Future<bool> verifyVpnEgress({
    required String serverId,
    required int deviceId,
    required VpnProtocol protocol,
    required String baselineFingerprint,
  }) async {
    verifyCalls += 1;
    expect(serverId, 'de-nue-1');
    expect(deviceId, 321);
    expect(protocol, this.protocol);
    expect(baselineFingerprint, 'a' * 64);
    return egressVerified;
  }

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
      'device_id': 321,
      'device_name': deviceName,
      'device_type': deviceType,
      'protocol': this.protocol == VpnProtocol.openVpn ? 'openvpn' : 'ikev2',
      'server_id': 'de-nue-1',
      'server_location': 'Nuremberg, Germany',
      'issued_at': DateTime.now().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'openvpn_config': this.protocol == VpnProtocol.openVpn
          ? 'client\ndev tun\ndhcp-option DNS 94.140.14.14\n'
          : '',
      'openvpn_username': this.protocol == VpnProtocol.openVpn
          ? 'swovpn-0123456789abcdef0123456789abcdef'
          : null,
      'openvpn_password': this.protocol == VpnProtocol.openVpn
          ? 'fresh-openvpn-password-012345'
          : null,
      'ikev2_config': this.protocol == VpnProtocol.ikev2
          ? 'connections { securewave {} }\n# endpoint_ip = 192.0.2.10\n# dns = 94.140.14.14\n'
          : '',
      'dns': _threatDnsFixture(),
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

Map<VpnProtocol, ProtocolAvailability> _allProtocolsAvailable() {
  return {
    for (final protocol in VpnProtocol.values)
      protocol: ProtocolAvailability(
        protocol: protocol,
        enabled: true,
        serverEnabled: true,
        platformSupported: true,
      ),
  };
}
