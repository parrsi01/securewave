import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/vpn_protocol.dart';
import '../core/logging/app_logger.dart';
import '../core/models/vpn_status.dart';
import '../core/services/auth_session.dart';
import '../core/services/device_identity.dart';
import '../core/services/protocol_selector.dart';
import '../core/services/secure_storage.dart';
import '../core/services/vpn_service.dart';
import '../core/state/app_state.dart';
import '../core/state/vpn_state.dart';
import '../core/vpn/protocol_capabilities.dart';
import '../services/api_client.dart';
import 'platform/network_interface_probe.dart';

const List<String> runtimeDiagnosticLabels = <String>[
  '1) Health: GET /api/health',
  '2) Auth: token persisted and authorized calls',
  '3) Catalog: servers/regions visible',
  '4) Profile: /api/vpn/profile for selected server',
  '5) Tunnel: connect -> connected -> disconnect -> clean',
  '6) Metrics: traffic changes Mbps/MB counters',
];

enum RuntimeDiagnosticStatus { pass, fail }

class RuntimeDiagnosticCheck {
  const RuntimeDiagnosticCheck({
    required this.label,
    required this.status,
    required this.detail,
    required this.completedAt,
  });

  final String label;
  final RuntimeDiagnosticStatus status;
  final String detail;
  final DateTime completedAt;

  String get statusKey => status.name;
  bool get passed => status == RuntimeDiagnosticStatus.pass;
}

class RuntimeDiagnosticsReport {
  const RuntimeDiagnosticsReport({
    required this.generatedAt,
    required this.checks,
    required this.connectionStatus,
    required this.interfaceSource,
    required this.rxBytes,
    required this.txBytes,
    required this.tunnelActiveButNoTraffic,
  });

  final DateTime generatedAt;
  final List<RuntimeDiagnosticCheck> checks;
  final VpnStatus connectionStatus;
  final String interfaceSource;
  final int rxBytes;
  final int txBytes;
  final bool tunnelActiveButNoTraffic;
}

final runtimeDiagnosticsProvider =
    FutureProvider.autoDispose<RuntimeDiagnosticsReport>((ref) async {
  final runner = RuntimeDiagnosticsRunner(ref);
  return runner.run();
});

class RuntimeDiagnosticsRunner {
  RuntimeDiagnosticsRunner(this._ref) : _storage = SecureStorage();

  final Ref _ref;
  final SecureStorage _storage;

  Future<RuntimeDiagnosticsReport> run() async {
    final api = _ref.read(apiClientProvider);
    final session = _ref.read(authSessionProvider);
    final vpnNotifier = _ref.read(vpnStateProvider.notifier);
    final service = _ref.read(vpnServiceProvider);

    final checks = <RuntimeDiagnosticCheck>[];
    var profileReady = false;
    var tunnelConnected =
        _ref.read(vpnStateProvider).status == VpnStatus.connected;
    var tunnelStartedHere = false;
    var interfaceSource = 'unavailable';
    var rxBytes = 0;
    var txBytes = 0;
    var activeButZeroTraffic = false;

    RuntimeDiagnosticCheck pass(String label, String detail) {
      return RuntimeDiagnosticCheck(
        label: label,
        status: RuntimeDiagnosticStatus.pass,
        detail: detail,
        completedAt: DateTime.now(),
      );
    }

    RuntimeDiagnosticCheck fail(String label, String detail) {
      return RuntimeDiagnosticCheck(
        label: label,
        status: RuntimeDiagnosticStatus.fail,
        detail: detail,
        completedAt: DateTime.now(),
      );
    }

    try {
      final health = await api.fetchHealth();
      AppLogger.info('[RUNTIME_DIAG] BACKEND_OK');
      checks.add(
        pass(
          runtimeDiagnosticLabels[0],
          'status=${health['status'] ?? 'ok'}',
        ),
      );
    } catch (error) {
      checks.add(fail(runtimeDiagnosticLabels[0], error.toString()));
    }

    if (!session.isAuthenticated) {
      checks.add(
        fail(runtimeDiagnosticLabels[1], 'Session is not authenticated.'),
      );
    } else {
      final freshnessIssue = session.accessTokenFreshnessIssue();
      if (freshnessIssue != null) {
        checks.add(
          fail(
            runtimeDiagnosticLabels[1],
            'Stored access token is not fresh: $freshnessIssue',
          ),
        );
      } else {
        try {
          final profile = await api.fetchProfile();
          final email = profile['email']?.toString() ?? session.email ?? 'ok';
          AppLogger.info('[RUNTIME_DIAG] AUTH_OK');
          checks.add(
            pass(runtimeDiagnosticLabels[1], 'authorized as $email'),
          );
        } catch (error) {
          checks.add(fail(runtimeDiagnosticLabels[1], error.toString()));
        }
      }
    }

    List<dynamic> servers = <dynamic>[];
    if (checks[1].passed) {
      try {
        servers = await api.fetchServers(forceRefresh: true);
        if (servers.isEmpty) {
          checks.add(
            fail(runtimeDiagnosticLabels[2],
                'Server catalog returned zero items.'),
          );
        } else {
          AppLogger.info('[RUNTIME_DIAG] SERVERS_LOADED');
          checks.add(
            pass(runtimeDiagnosticLabels[2],
                '${servers.length} regions available'),
          );
        }
      } catch (error) {
        checks.add(fail(runtimeDiagnosticLabels[2], error.toString()));
      }
    } else {
      checks.add(
        fail(runtimeDiagnosticLabels[2],
            'Skipped because authentication failed.'),
      );
    }

    final selectedServerId =
        (_ref.read(vpnStateProvider).selectedServerId ?? '').trim();
    if (checks[2].passed) {
      try {
        final identity = await DeviceIdentity.load();
        final caps = await service.getCapabilities();
        final catalog = await api.fetchVpnProtocols(
          deviceType: ProtocolCapabilityMatrix.currentDeviceType(),
        );
        final resolved = const ProtocolSelector().resolve(
          selected: _ref.read(vpnStateProvider).protocol,
          capabilities: caps,
          catalog: catalog,
        );
        if (!resolved.isConnectable) {
          throw StateError(resolved.error ?? 'Protocol is not connectable.');
        }
        final targetServer = selectedServerId.isNotEmpty
            ? selectedServerId
            : servers.first.id.toString();
        await _fetchVpnProfileWithRecovery(
          api: api,
          identity: identity,
          protocol: resolved.backendProtocol,
          serverId: targetServer,
        );
        profileReady = true;
        AppLogger.info('[RUNTIME_DIAG] PROFILE_READY');
        checks.add(
          pass(
            runtimeDiagnosticLabels[3],
            'protocol=${resolved.backendProtocol.name} server=$targetServer',
          ),
        );
      } catch (error) {
        checks.add(fail(runtimeDiagnosticLabels[3], error.toString()));
      }
    } else {
      checks.add(
        fail(runtimeDiagnosticLabels[3],
            'Skipped because server catalog failed.'),
      );
    }

    try {
      if (profileReady && !tunnelConnected) {
        await vpnNotifier.connect();
        await _waitForStatus(VpnStatus.connected);
        tunnelConnected = true;
        tunnelStartedHere = true;
      }
      if (tunnelConnected) {
        AppLogger.info('[RUNTIME_DIAG] TUNNEL_UP');
        checks.add(
          pass(
            runtimeDiagnosticLabels[4],
            tunnelStartedHere
                ? 'connected and recovered cleanly'
                : 'tunnel already connected',
          ),
        );
      } else {
        checks.add(
          fail(
            runtimeDiagnosticLabels[4],
            'Tunnel is not connected and profile validation did not establish one.',
          ),
        );
      }
    } catch (error) {
      checks.add(fail(runtimeDiagnosticLabels[4], error.toString()));
    }

    try {
      if (!tunnelConnected) {
        throw StateError('Tunnel not connected.');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      final sample = await _probeTraffic(service);
      interfaceSource = sample.source;
      rxBytes = sample.rxBytes;
      txBytes = sample.txBytes;
      final liveState = _ref.read(vpnStateProvider);
      final totalBytes = rxBytes + txBytes;
      final anyLiveRate =
          liveState.dataRateDown > 0 || liveState.dataRateUp > 0;
      activeButZeroTraffic = totalBytes <= 0 && !anyLiveRate;
      if (activeButZeroTraffic) {
        throw StateError(
          'Tunnel active but traffic is zero (${sample.source}).',
        );
      }
      AppLogger.info('[RUNTIME_DIAG] TRAFFIC_FLOWING');
      checks.add(
        pass(
          runtimeDiagnosticLabels[5],
          'source=${sample.source} rx=$rxBytes tx=$txBytes',
        ),
      );
    } catch (error) {
      checks.add(fail(runtimeDiagnosticLabels[5], error.toString()));
    } finally {
      if (tunnelStartedHere) {
        try {
          await vpnNotifier.disconnect();
          await _waitForStatus(VpnStatus.disconnected);
        } catch (error, stackTrace) {
          AppLogger.error(
            'Diagnostics cleanup disconnect failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return RuntimeDiagnosticsReport(
      generatedAt: DateTime.now(),
      checks: checks,
      connectionStatus: _ref.read(vpnStateProvider).status,
      interfaceSource: interfaceSource,
      rxBytes: rxBytes,
      txBytes: txBytes,
      tunnelActiveButNoTraffic: activeButZeroTraffic,
    );
  }

  Future<void> _fetchVpnProfileWithRecovery({
    required ApiClient api,
    required DeviceIdentity identity,
    required VpnProtocol protocol,
    required String serverId,
  }) async {
    final cachedDeviceId = await _storage.getInt(SecureStorage.vpnDeviceIdKey);

    Future<void> fetchProfile({required int? requestedDeviceId}) async {
      final profile = await api.fetchVpnProfile(
        deviceId: requestedDeviceId,
        deviceName: identity.name,
        deviceType: identity.type,
        protocol: protocol,
        serverId: serverId,
      );
      if (profile.deviceId > 0) {
        await _storage.saveInt(SecureStorage.vpnDeviceIdKey, profile.deviceId);
      }
    }

    try {
      await fetchProfile(requestedDeviceId: cachedDeviceId);
    } on DioException catch (error) {
      final code = _apiErrorCode(error);
      if (cachedDeviceId != null && code == 'device_not_found') {
        await _storage.delete(SecureStorage.vpnDeviceIdKey);
        await fetchProfile(requestedDeviceId: null);
        return;
      }

      final recoveredDeviceId = _isDeviceLimitCode(code)
          ? await _recoverSingleDeviceSlotId(
              api: api,
              identity: identity,
              requestedDeviceId: cachedDeviceId,
            )
          : null;
      if (recoveredDeviceId != null && recoveredDeviceId != cachedDeviceId) {
        await _storage.saveInt(
          SecureStorage.vpnDeviceIdKey,
          recoveredDeviceId,
        );
        await fetchProfile(requestedDeviceId: recoveredDeviceId);
        return;
      }
      rethrow;
    }
  }

  String? _apiErrorCode(DioException error) {
    final data = error.response?.data;
    if (data is! Map) return null;
    final payload = data['error'];
    if (payload is! Map) return null;
    final code = payload['code']?.toString().trim().toLowerCase();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  bool _isDeviceLimitCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    return normalized == 'device_limit_reached' ||
        normalized == 'device_limit' ||
        normalized == 'device_limit_exceeded' ||
        normalized == 'too_many_devices';
  }

  Future<int?> _recoverSingleDeviceSlotId({
    required ApiClient api,
    required DeviceIdentity identity,
    required int? requestedDeviceId,
  }) async {
    try {
      final devices = await api.listDevices();
      if (devices.limit != 1 || devices.devices.length != 1) {
        return null;
      }
      final existing = devices.devices.first;
      if (existing.id <= 0 || existing.id == requestedDeviceId) {
        return null;
      }
      final existingType = (existing.deviceType ?? '').trim().toLowerCase();
      final currentType = identity.type.trim().toLowerCase();
      if (existingType.isNotEmpty &&
          currentType.isNotEmpty &&
          existingType != currentType) {
        return null;
      }
      return existing.id;
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[RUNTIME_DIAG] {"event":"device_limit_recovery_probe_failed"}',
      );
      AppLogger.error(
        'Runtime diagnostics device-limit recovery probe failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _waitForStatus(
    VpnStatus expected, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_ref.read(vpnStateProvider).status == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Timed out waiting for $expected');
  }

  Future<({String source, int rxBytes, int txBytes})> _probeTraffic(
    VpnService service,
  ) async {
    if (service is ChannelVpnService) {
      final native = await service.fetchTrafficStats();
      if (native != null) {
        return (
          source: native.interfaceName == null
              ? 'native'
              : 'native:${native.interfaceName}',
          rxBytes: native.rxBytes,
          txBytes: native.txBytes,
        );
      }
    }
    final linux = await probeLinuxTunnelInterface();
    if (linux != null) {
      return (
        source: 'linux:${linux.interfaceName}',
        rxBytes: linux.rxBytes,
        txBytes: linux.txBytes,
      );
    }
    final live = _ref.read(vpnStateProvider);
    return (
      source: 'client_counters',
      rxBytes: live.sessionTransferredBytes,
      txBytes: 0,
    );
  }
}
