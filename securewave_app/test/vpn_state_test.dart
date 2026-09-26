import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/protocol_availability.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_stubSecureStorage);

  test('VpnStateNotifier transitions through WireGuard connect and disconnect',
      () async {
    final service = _FakeVpnService();
    final api = _UsageApiClient();
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
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
    expect(service.refreshedProtocols, [VpnProtocol.wireGuard]);
  });

  test('native WireGuard usage reporting sends counter deltas', () async {
    final service = _NativeUsageVpnService([
      const VpnTrafficStats(rxBytes: 1000, txBytes: 500),
      const VpnTrafficStats(rxBytes: 1300, txBytes: 700),
    ]);
    final api = _UsageApiClient();
    final container = ProviderContainer(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    await notifier.connect();
    for (var attempt = 0;
        attempt < 30 && api.usageReports.isEmpty;
        attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(api.usageReports, isNotEmpty);
    expect(api.usageReports.first.bytesSent, 200);
    expect(api.usageReports.first.bytesReceived, 300);

    await notifier.disconnect();
    expect(api.finalizedSessionIds, [42]);
  }, testOn: 'linux');
}

void _stubSecureStorage() {
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
}

class _FakeVpnService extends VpnService {
  VpnStatus _status = VpnStatus.disconnected;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) =>
      protocol == VpnProtocol.wireGuard;

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async =>
      canConnectProtocol(protocol);

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) =>
      canConnectProtocol(protocol) ? null : 'Only WireGuard is available.';

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
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
}

class _InitializationTrackingVpnService extends _FakeVpnService {
  final _release = Completer<void>();
  final refreshedProtocols = <VpnProtocol>[];

  void releaseAvailabilityChecks() => _release.complete();

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async {
    refreshedProtocols.add(protocol);
    await _release.future;
    return true;
  }
}

class _NativeUsageVpnService extends VpnService {
  _NativeUsageVpnService(this._stats);

  final List<VpnTrafficStats> _stats;
  var _status = VpnStatus.disconnected;
  var _index = 0;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async =>
      true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
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
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    final value = _stats[_index.clamp(0, _stats.length - 1)];
    _index += 1;
    return value;
  }

  @override
  VpnStatus getStatus() => _status;
}

class _UsageApiClient extends ApiClient {
  _UsageApiClient() : super(AppConfig.defaults());

  final usageReports = <_UsageReport>[];
  final finalizedSessionIds = <int>[];

  @override
  Future<Map<VpnProtocol, ProtocolAvailability>> fetchProtocolAvailability({
    String? deviceType,
  }) async =>
      {
        VpnProtocol.wireGuard: const ProtocolAvailability(
          protocol: VpnProtocol.wireGuard,
          enabled: true,
          serverEnabled: true,
          platformSupported: true,
        ),
      };

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
      'device_name': deviceName,
      'device_type': deviceType,
      'protocol': 'wireguard',
      'server_id': serverId ?? 'de-nue-1',
      'server_location': 'Nuremberg, Germany',
      'issued_at': DateTime.now().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      'wireguard_config':
          '[Interface]\nPrivateKey = test\n[Peer]\nPublicKey = test\n',
      'dns': {
        'servers': ['94.140.14.14'],
      },
      'peer_registered': true,
    });
  }

  @override
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {}

  @override
  Future<void> notifyVpnDisconnected() async {}

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
    usageReports.add(_UsageReport(bytesSent, bytesReceived));
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

class _UsageReport {
  const _UsageReport(this.bytesSent, this.bytesReceived);

  final int bytesSent;
  final int bytesReceived;
}
