import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../models/diagnostics.dart';
import '../models/server_region.dart';
import '../models/traffic_snapshot.dart';
import '../models/tunnel_health_snapshot.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../services/auth_session.dart';
import '../services/diagnostics_service.dart';
import '../services/secure_storage.dart';
import '../services/traffic_stats_service.dart';
import '../services/tunnel_status_service.dart';
import '../services/vm_environment.dart';
import '../services/vpn_service.dart';
import '../utils/api_error.dart';
import 'app_state.dart';
import 'client_settings_state.dart';
import 'network_lock_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.stage = VpnConnectionStage.idle,
    this.selectedServerId,
    this.protocol = VpnProtocol.wireGuard,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.sessionDownloadBytes = 0,
    this.sessionUploadBytes = 0,
    this.lifetimeDownloadBytes = 0,
    this.lifetimeUploadBytes = 0,
    this.connectionDuration = Duration.zero,
    this.lastConnectedAt,
    this.errorMessage,
    this.vmSafeMode = false,
    this.checks = const <String, DiagnosticResult>{},
    this.interfaceName,
    this.interfaceOk = false,
    this.routingOk = false,
    this.reconnectAttempt = 0,
    this.desiredOn = false,
    this.activeProtocol,
    this.networkLockActive = false,
    this.networkLockReason,
    this.diagnosticsUpdatedAt,
    this.statusDetail,
  });

  final VpnStatus status;
  final VpnConnectionStage stage;
  final String? selectedServerId;
  final VpnProtocol protocol;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final int sessionDownloadBytes;
  final int sessionUploadBytes;
  final int lifetimeDownloadBytes;
  final int lifetimeUploadBytes;
  final Duration connectionDuration;
  final DateTime? lastConnectedAt;
  final String? errorMessage;
  final bool vmSafeMode;
  final Map<String, DiagnosticResult> checks;
  final String? interfaceName;
  final bool interfaceOk;
  final bool routingOk;
  final int reconnectAttempt;
  final bool desiredOn;
  final VpnProtocol? activeProtocol;
  final bool networkLockActive;
  final String? networkLockReason;
  final DateTime? diagnosticsUpdatedAt;
  final String? statusDetail;

  bool get isConnected => status == VpnStatus.connected;
  bool get canConnect =>
      status == VpnStatus.disconnected || status == VpnStatus.error;
  bool get canDisconnect =>
      status == VpnStatus.connected ||
      status == VpnStatus.connecting ||
      status == VpnStatus.reconnecting;

  VpnState copyWith({
    VpnStatus? status,
    VpnConnectionStage? stage,
    String? selectedServerId,
    VpnProtocol? protocol,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    int? sessionDownloadBytes,
    int? sessionUploadBytes,
    int? lifetimeDownloadBytes,
    int? lifetimeUploadBytes,
    Duration? connectionDuration,
    DateTime? lastConnectedAt,
    String? errorMessage,
    bool? vmSafeMode,
    Map<String, DiagnosticResult>? checks,
    String? interfaceName,
    bool? interfaceOk,
    bool? routingOk,
    int? reconnectAttempt,
    bool? desiredOn,
    VpnProtocol? activeProtocol,
    bool? networkLockActive,
    String? networkLockReason,
    DateTime? diagnosticsUpdatedAt,
    String? statusDetail,
    bool clearError = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      stage: stage ?? this.stage,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      protocol: protocol ?? this.protocol,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      sessionDownloadBytes: sessionDownloadBytes ?? this.sessionDownloadBytes,
      sessionUploadBytes: sessionUploadBytes ?? this.sessionUploadBytes,
      lifetimeDownloadBytes:
          lifetimeDownloadBytes ?? this.lifetimeDownloadBytes,
      lifetimeUploadBytes: lifetimeUploadBytes ?? this.lifetimeUploadBytes,
      connectionDuration: connectionDuration ?? this.connectionDuration,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      vmSafeMode: vmSafeMode ?? this.vmSafeMode,
      checks: checks ?? this.checks,
      interfaceName: interfaceName ?? this.interfaceName,
      interfaceOk: interfaceOk ?? this.interfaceOk,
      routingOk: routingOk ?? this.routingOk,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      desiredOn: desiredOn ?? this.desiredOn,
      activeProtocol: activeProtocol ?? this.activeProtocol,
      networkLockActive: networkLockActive ?? this.networkLockActive,
      networkLockReason: networkLockReason ?? this.networkLockReason,
      diagnosticsUpdatedAt: diagnosticsUpdatedAt ?? this.diagnosticsUpdatedAt,
      statusDetail: statusDetail ?? this.statusDetail,
    );
  }
}

final vpnStateProvider =
    StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref)
      : _storage = SecureStorage(),
        super(
          VpnState(
            status: _ref.read(vpnServiceProvider).getStatus(),
            vmSafeMode: _ref.read(vmEnvironmentProvider).safeModeEnabled,
          ),
        ) {
    _restoreState();
  }

  final Ref _ref;
  final SecureStorage _storage;

  Timer? _durationTimer;
  Timer? _trafficTimer;
  Timer? _nativeStatusTimer;
  Timer? _reconnectTimer;
  TrafficSnapshot? _lastTrafficSnapshot;
  bool _networkAvailable = true;
  bool _recoveryArmed = false;
  int _reconnectAttempts = 0;
  final Map<String, int> _serverFailureCounts = <String, int>{};
  DateTime? _lastUserActionAt;

  static const List<Duration> _reconnectBackoff = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  static const Set<VpnStatus> _connectableStates = <VpnStatus>{
    VpnStatus.disconnected,
    VpnStatus.error,
  };
  static const Set<VpnStatus> _disconnectableStates = <VpnStatus>{
    VpnStatus.connected,
    VpnStatus.connecting,
    VpnStatus.reconnecting,
  };

  Future<void> _restoreState() async {
    final storedProtocol =
        await _storage.getString(SecureStorage.vpnProtocolKey);
    final storedServer =
        await _storage.getString(SecureStorage.selectedServerKey);
    final storedStatus = await _storage.getString(SecureStorage.vpnStatusKey);
    final storedStage = await _storage.getString(SecureStorage.vpnStageKey);
    final connectedAtRaw =
        await _storage.getString(SecureStorage.vpnConnectedAtKey);
    final desiredOn =
        await _storage.getBool(SecureStorage.vpnDesiredOnKey) ?? false;
    final diagnosticsHistory =
        await _storage.getString(SecureStorage.vpnDiagnosticsHistoryKey);
    final restoredDiagnostics = _decodeDiagnosticsHistory(diagnosticsHistory);

    if (!mounted) {
      return;
    }

    state = state.copyWith(
      protocol: vpnProtocolFromStorage(storedProtocol),
      selectedServerId: storedServer,
      status: _statusFromStorage(storedStatus),
      stage: _stageFromStorage(storedStage),
      lastConnectedAt: connectedAtRaw == null || connectedAtRaw.isEmpty
          ? null
          : DateTime.tryParse(connectedAtRaw),
      desiredOn: desiredOn,
      checks: restoredDiagnostics,
      diagnosticsUpdatedAt: restoredDiagnostics.isEmpty ? null : DateTime.now(),
    );

    await _syncWithNativeStatus(reason: 'restore');

    if (!mounted) {
      return;
    }

    final auth = _ref.read(authSessionProvider);
    final settings = _ref.read(clientSettingsProvider);
    if (settings.bestEffortKillSwitch &&
        desiredOn &&
        auth.isAuthenticated &&
        state.status != VpnStatus.connected) {
      _engageKillSwitch(
          'Best-effort kill switch is active until SecureWave reconnects.');
    }

    if (state.status == VpnStatus.connected) {
      _ref.read(networkLockProvider.notifier).release();
      _startMonitoring();
      return;
    }

    if (desiredOn &&
        settings.autoConnect &&
        auth.isAuthenticated &&
        (state.status == VpnStatus.connecting ||
            state.status == VpnStatus.reconnecting ||
            state.status == VpnStatus.disconnected)) {
      _recoveryArmed = true;
      await _scheduleReconnect(
        reason: 'Ready to reconnect after restart.',
        immediate: true,
      );
    } else if (desiredOn &&
        auth.isAuthenticated &&
        state.status == VpnStatus.disconnected) {
      state = state.copyWith(
        errorMessage: 'Ready to reconnect.',
        statusDetail: 'Last session was restored. Tap Reconnect now to resume.',
      );
    }
  }

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId, clearError: true);
    if (serverId != null && serverId.isNotEmpty) {
      unawaited(_storage.saveString(SecureStorage.selectedServerKey, serverId));
    }
  }

  Future<void> selectProtocol(VpnProtocol protocol) async {
    state = state.copyWith(
      protocol: protocol,
      activeProtocol: protocol == VpnProtocol.auto ? null : protocol,
      clearError: true,
    );
    await _storage.saveString(
      SecureStorage.vpnProtocolKey,
      vpnProtocolStorageValue(protocol),
    );
  }

  Future<void> connect() async {
    if (!_connectableStates.contains(state.status) || state.isBusy) {
      return;
    }
    if (_shouldThrottleUserAction()) {
      return;
    }
    if (state.selectedServerId == null || state.selectedServerId!.isEmpty) {
      state = state.copyWith(
          errorMessage: 'Select a server region before connecting.');
      return;
    }

    _recoveryArmed = false;
    _cancelReconnectTimer();
    _reconnectAttempts = 0;
    state = state.copyWith(reconnectAttempt: 0, desiredOn: true);
    await _storage.saveBool(SecureStorage.vpnDesiredOnKey, true);
    await _runConnectionCycle(isReconnect: false);
  }

  Future<void> reconnectAfterResume({String? reason}) async {
    if (state.selectedServerId == null || state.selectedServerId!.isEmpty) {
      return;
    }
    _recoveryArmed = true;
    await _scheduleReconnect(reason: reason ?? 'App resumed.', immediate: true);
  }

  Future<void> reconnectNow() async {
    if (state.selectedServerId == null || state.selectedServerId!.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Choose a server before reconnecting.',
      );
      return;
    }
    _cancelReconnectTimer();
    _recoveryArmed = true;
    await _scheduleReconnect(
        reason: 'Manual reconnect requested.', immediate: true);
  }

  Future<void> disconnect() async {
    if (!_disconnectableStates.contains(state.status) || state.isBusy) {
      return;
    }
    if (_shouldThrottleUserAction()) {
      return;
    }

    _recoveryArmed = false;
    _cancelReconnectTimer();
    state = state.copyWith(isBusy: true, clearError: true);
    await _storage.saveBool(SecureStorage.vpnDesiredOnKey, false);
    _ref.read(networkLockProvider.notifier).release();
    await _transitionTo(
        VpnStatus.disconnecting, VpnConnectionStage.tunnelStart);

    try {
      final nextStatus = await _ref.read(vpnServiceProvider).disconnect();
      final nativeSnapshot =
          await _ref.read(tunnelStatusServiceProvider).getStatus();
      await _transitionTo(nextStatus, VpnConnectionStage.idle);
      _applyNativeSnapshot(nativeSnapshot);
      _stopMonitoring(resetSession: true);
      _reconnectAttempts = 0;
      state = state.copyWith(
        isBusy: false,
        connectionDuration: Duration.zero,
        lastConnectedAt: null,
        reconnectAttempt: 0,
        desiredOn: false,
        networkLockActive: false,
        networkLockReason: null,
      );
      await refreshDiagnostics();
    } catch (error, stackTrace) {
      await _fail(error, stackTrace, allowRecovery: false);
    } finally {
      await _persistState();
    }
  }

  Future<void> refreshDiagnostics() async {
    final checks = await _ref.read(diagnosticsServiceProvider).run();
    if (!mounted) {
      return;
    }
    final mapped = <String, DiagnosticResult>{
      for (final DiagnosticResult check in checks) check.key: check,
    };
    state = state.copyWith(
      checks: mapped,
      diagnosticsUpdatedAt: DateTime.now(),
    );
    await _storage.saveString(
      SecureStorage.vpnDiagnosticsHistoryKey,
      _encodeDiagnosticsHistory(mapped),
    );
  }

  void onNetworkAvailabilityChanged(bool isAvailable) {
    _networkAvailable = isAvailable;
    AppLogger.routing(
      'network_path_changed',
      fields: <String, Object?>{'available': isAvailable},
    );
    if (!isAvailable &&
        state.status == VpnStatus.connected &&
        _ref.read(clientSettingsProvider).autoReconnect) {
      _recoveryArmed = true;
      unawaited(_scheduleReconnect(
          reason: 'Network path changed.', immediate: false));
    }
  }

  void pauseRateUpdates() {
    _durationTimer?.cancel();
    _trafficTimer?.cancel();
    _nativeStatusTimer?.cancel();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected) {
      _startMonitoring();
    }
  }

  Future<void> _runConnectionCycle({
    required bool isReconnect,
    String? resumeReason,
  }) async {
    final VpnStatus nextStatus =
        isReconnect ? VpnStatus.reconnecting : VpnStatus.connecting;
    final settings = _ref.read(clientSettingsProvider);
    state = state.copyWith(
      isBusy: true,
      vmSafeMode: _ref.read(vmEnvironmentProvider).safeModeEnabled,
      clearError: true,
      reconnectAttempt: _reconnectAttempts,
      desiredOn: true,
    );

    try {
      await _transitionTo(nextStatus, VpnConnectionStage.login);

      final AuthSession auth = _ref.read(authSessionProvider);
      final AppConfig config = _ref.read(appConfigProvider);
      if (!auth.isAuthenticated && !config.useMockApi) {
        throw const ApiClientException(
          'auth_missing',
          'Authentication expired. Please sign in again.',
        );
      }
      AppLogger.auth('session_validated',
          fields: <String, Object?>{'authenticated': auth.isAuthenticated});

      final ApiClient api = _ref.read(apiClientProvider);
      await _transitionTo(nextStatus, VpnConnectionStage.fetchServers);
      final servers = await api.fetchServers(
        forceRefresh: true,
        allowWhenLocked: true,
      );
      final serverId = state.selectedServerId;
      final hasServer = servers.any((server) => server.id == serverId);
      if (!hasServer && !config.useMockApi) {
        throw const ApiClientException(
          'server_missing',
          'Selected server is no longer available.',
        );
      }
      AppLogger.server(
        'catalog_loaded',
        fields: <String, Object?>{
          'count': servers.length,
          'selected': serverId
        },
      );

      await _transitionTo(nextStatus, VpnConnectionStage.fetchProfile);
      final String profile = await api.fetchVpnProfile(
        serverId: serverId,
        allowWhenLocked: true,
      );

      await _transitionTo(nextStatus, VpnConnectionStage.protocolReady);
      if (state.vmSafeMode) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      if (!_networkAvailable && state.vmSafeMode) {
        throw const ApiClientException(
          'network_unavailable',
          'Network path is unstable. VM safe mode delayed tunnel startup.',
        );
      }

      await _transitionTo(nextStatus, VpnConnectionStage.tunnelStart);
      final vpnService = _ref.read(vpnServiceProvider);
      final protocolCandidates =
          _protocolCandidates(state.protocol, vpnService.supportedProtocols);
      VpnStatus connectedStatus = VpnStatus.error;
      Object? lastProtocolError;
      VpnProtocol? resolvedProtocol;

      for (final protocol in protocolCandidates) {
        try {
          connectedStatus = await vpnService.connect(
            protocol: protocol,
            config: profile,
          );
          resolvedProtocol = protocol;
          if (connectedStatus == VpnStatus.connected) {
            break;
          }
          lastProtocolError = VpnServiceException(
            'unexpected_status',
            'VPN service returned ${connectedStatus.name} instead of connected.',
          );
        } catch (error) {
          lastProtocolError = error;
          if (state.protocol != VpnProtocol.auto) {
            break;
          }
        }
      }

      if (connectedStatus != VpnStatus.connected || resolvedProtocol == null) {
        throw lastProtocolError ??
            VpnServiceException(
              'protocol_unavailable',
              'No supported protocol could start the tunnel.',
            );
      }

      final TunnelHealthSnapshot nativeSnapshot =
          await _ref.read(tunnelStatusServiceProvider).getStatus();
      if (vpnService.isNativeAvailable &&
          !config.useMockApi &&
          nativeSnapshot.status != VpnStatus.connected &&
          nativeSnapshot.status != VpnStatus.connecting) {
        throw VpnServiceException(
          'native_status_mismatch',
          'Native tunnel did not report a connected state.',
        );
      }
      if (state.vmSafeMode && !nativeSnapshot.routingOk) {
        throw const ApiClientException(
          'vm_route_conflict',
          'VM route conflict detected. Default route is not using the tunnel.',
        );
      }

      await _transitionTo(VpnStatus.connected, VpnConnectionStage.tunnelActive);
      final DateTime connectedAt = DateTime.now();
      _ref.read(networkLockProvider.notifier).release();
      state = state.copyWith(
        lastConnectedAt: connectedAt,
        connectionDuration: Duration.zero,
        reconnectAttempt: 0,
        activeProtocol: resolvedProtocol,
        statusDetail: settings.bestEffortKillSwitch
            ? 'Best-effort kill switch ready.'
            : nativeSnapshot.details,
        networkLockActive: false,
        networkLockReason: null,
      );
      _applyNativeSnapshot(nativeSnapshot);
      _reconnectAttempts = 0;
      _serverFailureCounts[state.selectedServerId ?? ''] = 0;
      _recoveryArmed = true;
      _startMonitoring();
      await refreshDiagnostics();
      if (resumeReason != null) {
        AppLogger.tunnel('reconnect_completed',
            fields: <String, Object?>{'reason': resumeReason});
      }
    } catch (error, stackTrace) {
      await _fail(error, stackTrace,
          allowRecovery:
              (isReconnect || _recoveryArmed) && settings.autoReconnect,
          servers:
              state.selectedServerId == null || state.selectedServerId!.isEmpty
                  ? const <ServerRegion>[]
                  : await _loadServersForRecovery());
    } finally {
      if (mounted) {
        state = state.copyWith(isBusy: false);
      }
      await _persistState();
    }
  }

  Future<void> _fail(
    Object error,
    StackTrace stackTrace, {
    required bool allowRecovery,
    List<ServerRegion> servers = const <ServerRegion>[],
  }) async {
    _stopMonitoring(resetSession: false);
    await _transitionTo(VpnStatus.error, state.stage);
    if (!mounted) {
      return;
    }
    final failureMessage = _vpnErrorMessage(error);
    final killSwitchEnabled =
        _ref.read(clientSettingsProvider).bestEffortKillSwitch;
    if (killSwitchEnabled && state.desiredOn) {
      _engageKillSwitch(
        'Best-effort kill switch is holding app traffic until SecureWave reconnects.',
      );
    }
    _recordServerFailure(state.selectedServerId);
    final failoverServer = _selectFailoverServer(servers);
    state = state.copyWith(
      errorMessage: failureMessage,
      statusDetail: failoverServer != null
          ? 'Failing over to ${failoverServer.name} after repeated tunnel failures.'
          : failureMessage,
    );
    AppLogger.error(
      'vpn_flow_failed',
      error: error,
      stackTrace: stackTrace,
      category: AppLogCategory.vpnState,
      fields: <String, Object?>{
        'stage': state.stage.name,
        'server': state.selectedServerId,
        'protocol': vpnProtocolStorageValue(state.protocol),
      },
    );
    await refreshDiagnostics();
    if (allowRecovery && _recoveryArmed) {
      if (failoverServer != null) {
        selectServer(failoverServer.id);
      }
      await _scheduleReconnect(
        reason: failoverServer != null
            ? 'Server failover triggered after repeated tunnel failures.'
            : failureMessage,
        immediate: false,
      );
    }
  }

  Future<void> _transitionTo(VpnStatus status, VpnConnectionStage stage) async {
    final VpnStatus previous = state.status;
    _validateTransition(previous, status);
    if (!mounted) {
      return;
    }
    state = state.copyWith(status: status, stage: stage);
    AppLogger.vpnStateTransition(
      previous: previous.name.toUpperCase(),
      next: status.name.toUpperCase(),
      server: state.selectedServerId,
      protocol: vpnProtocolStorageValue(state.protocol),
    );
    await _persistState();
  }

  void _validateTransition(VpnStatus current, VpnStatus next) {
    const Map<VpnStatus, Set<VpnStatus>> allowed = <VpnStatus, Set<VpnStatus>>{
      VpnStatus.disconnected: <VpnStatus>{
        VpnStatus.connecting,
        VpnStatus.reconnecting,
        VpnStatus.error,
      },
      VpnStatus.connecting: <VpnStatus>{
        VpnStatus.connected,
        VpnStatus.disconnecting,
        VpnStatus.error,
      },
      VpnStatus.connected: <VpnStatus>{
        VpnStatus.disconnecting,
        VpnStatus.reconnecting,
        VpnStatus.error,
      },
      VpnStatus.disconnecting: <VpnStatus>{
        VpnStatus.disconnected,
        VpnStatus.error,
      },
      VpnStatus.reconnecting: <VpnStatus>{
        VpnStatus.connected,
        VpnStatus.disconnecting,
        VpnStatus.error,
      },
      VpnStatus.error: <VpnStatus>{
        VpnStatus.disconnected,
        VpnStatus.connecting,
        VpnStatus.reconnecting,
      },
    };

    if (current == next) {
      return;
    }
    if (!(allowed[current]?.contains(next) ?? false)) {
      throw StateError(
          'Invalid VPN transition: ${current.name} -> ${next.name}');
    }
  }

  void _startMonitoring() {
    _durationTimer?.cancel();
    _trafficTimer?.cancel();
    _nativeStatusTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? connectedAt = state.lastConnectedAt;
      if (connectedAt == null || !mounted) {
        return;
      }
      state = state.copyWith(
          connectionDuration: DateTime.now().difference(connectedAt));
    });

    final trafficPollingInterval = state.vmSafeMode && !state.interfaceOk
        ? const Duration(seconds: 3)
        : const Duration(seconds: 1);

    _trafficTimer = Timer.periodic(trafficPollingInterval, (_) async {
      final TrafficSnapshot sample = await _ref
          .read(trafficStatsServiceProvider)
          .sample(preferredInterface: state.interfaceName);
      final TrafficSnapshot? previous = _lastTrafficSnapshot;
      _lastTrafficSnapshot = sample;
      if (previous == null || !mounted) {
        return;
      }
      final int elapsed =
          sample.timestamp.difference(previous.timestamp).inMilliseconds;
      if (elapsed <= 0) {
        return;
      }
      final int rxDelta =
          (sample.receivedBytes - previous.receivedBytes).clamp(0, 1 << 62);
      final int txDelta = (sample.transmittedBytes - previous.transmittedBytes)
          .clamp(0, 1 << 62);
      final TrafficRate rate = TrafficRate(
        downloadBytesPerSecond: rxDelta / (elapsed / 1000),
        uploadBytesPerSecond: txDelta / (elapsed / 1000),
        sessionDownloadBytes: state.sessionDownloadBytes + rxDelta,
        sessionUploadBytes: state.sessionUploadBytes + txDelta,
      );

      state = state.copyWith(
        dataRateDown: rate.downloadBytesPerSecond,
        dataRateUp: rate.uploadBytesPerSecond,
        sessionDownloadBytes: rate.sessionDownloadBytes,
        sessionUploadBytes: rate.sessionUploadBytes,
        lifetimeDownloadBytes: state.lifetimeDownloadBytes + rxDelta,
        lifetimeUploadBytes: state.lifetimeUploadBytes + txDelta,
        statusDetail: sample.countersAvailable
            ? state.statusDetail
            : (sample.statusMessage ?? 'Native traffic counters unavailable.'),
      );
    });

    _nativeStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _syncWithNativeStatus(reason: 'poll');
    });
  }

  void _stopMonitoring({required bool resetSession}) {
    _durationTimer?.cancel();
    _trafficTimer?.cancel();
    _nativeStatusTimer?.cancel();
    _durationTimer = null;
    _trafficTimer = null;
    _nativeStatusTimer = null;
    _lastTrafficSnapshot = null;
    if (!mounted) {
      return;
    }
    state = state.copyWith(
      dataRateDown: 0,
      dataRateUp: 0,
      sessionDownloadBytes: resetSession ? 0 : state.sessionDownloadBytes,
      sessionUploadBytes: resetSession ? 0 : state.sessionUploadBytes,
      connectionDuration:
          resetSession ? Duration.zero : state.connectionDuration,
      stage: resetSession ? VpnConnectionStage.idle : state.stage,
      status: resetSession ? VpnStatus.disconnected : state.status,
    );
  }

  Future<void> _syncWithNativeStatus({required String reason}) async {
    final TunnelHealthSnapshot snapshot =
        await _ref.read(tunnelStatusServiceProvider).getStatus();
    _applyNativeSnapshot(snapshot);
    if (!mounted) {
      return;
    }
    if (snapshot.status == VpnStatus.connected &&
        state.status != VpnStatus.connected &&
        state.desiredOn) {
      state = state.copyWith(
        status: VpnStatus.connected,
        stage: VpnConnectionStage.tunnelActive,
        lastConnectedAt: snapshot.connectedSince ?? DateTime.now(),
        networkLockActive: false,
        networkLockReason: null,
      );
      _ref.read(networkLockProvider.notifier).release();
      _startMonitoring();
      return;
    }
    if (state.status == VpnStatus.connected &&
        snapshot.status == VpnStatus.disconnected &&
        _recoveryArmed) {
      AppLogger.tunnel(
        'native_drop_detected',
        fields: <String, Object?>{
          'reason': reason,
          'interface': snapshot.interfaceName
        },
      );
      if (_ref.read(clientSettingsProvider).bestEffortKillSwitch) {
        _engageKillSwitch(
          'Best-effort kill switch is active because the tunnel dropped unexpectedly.',
        );
      }
      await _scheduleReconnect(
          reason: 'Native tunnel dropped.', immediate: false);
    }
  }

  void _applyNativeSnapshot(TunnelHealthSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    final connectedSince = snapshot.connectedSince;
    state = state.copyWith(
      interfaceName: snapshot.interfaceName,
      interfaceOk: snapshot.interfaceOk,
      routingOk: snapshot.routingOk,
      lastConnectedAt: connectedSince ?? state.lastConnectedAt,
      statusDetail:
          snapshot.lastError ?? snapshot.details ?? state.statusDetail,
    );
  }

  Future<void> _scheduleReconnect({
    required String reason,
    required bool immediate,
  }) async {
    if (!_recoveryArmed ||
        !state.desiredOn ||
        state.selectedServerId == null ||
        state.selectedServerId!.isEmpty ||
        !mounted) {
      return;
    }
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    if (_reconnectAttempts >= _reconnectBackoff.length) {
      await _transitionTo(VpnStatus.error, state.stage);
      if (mounted) {
        state = state.copyWith(
          errorMessage: 'Reconnect failed after 5 attempts.',
          reconnectAttempt: _reconnectAttempts,
          statusDetail:
              'Reconnect now is available if the network is stable again.',
        );
      }
      return;
    }

    final Duration delay =
        immediate ? Duration.zero : _reconnectBackoff[_reconnectAttempts];
    _reconnectAttempts += 1;
    if (mounted) {
      state = state.copyWith(reconnectAttempt: _reconnectAttempts);
    }
    AppLogger.tunnel(
      'reconnect_scheduled',
      fields: <String, Object?>{
        'attempt': _reconnectAttempts,
        'delay_ms': delay.inMilliseconds,
        'reason': reason,
      },
    );

    if (state.status == VpnStatus.connected) {
      await _transitionTo(VpnStatus.reconnecting, VpnConnectionStage.login);
    }

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!mounted) {
        return;
      }
      unawaited(_runConnectionCycle(isReconnect: true, resumeReason: reason));
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _persistState() async {
    await _storage.saveString(SecureStorage.vpnStatusKey, state.status.name);
    await _storage.saveString(SecureStorage.vpnStageKey, state.stage.name);
    await _storage.saveBool(SecureStorage.vpnDesiredOnKey, state.desiredOn);
    await _storage.saveString(
      SecureStorage.vpnConnectedAtKey,
      state.lastConnectedAt?.toIso8601String() ?? '',
    );
  }

  VpnStatus _statusFromStorage(String? value) {
    return VpnStatus.values.firstWhere(
      (VpnStatus status) => status.name == value,
      orElse: () => VpnStatus.disconnected,
    );
  }

  VpnConnectionStage _stageFromStorage(String? value) {
    return VpnConnectionStage.values.firstWhere(
      (VpnConnectionStage stage) => stage.name == value,
      orElse: () => VpnConnectionStage.idle,
    );
  }

  String _vpnErrorMessage(Object error) {
    return ApiError.messageFrom(
      error,
      fallback: 'Unable to complete the VPN request right now.',
    );
  }

  bool _shouldThrottleUserAction() {
    final now = DateTime.now();
    final lastActionAt = _lastUserActionAt;
    _lastUserActionAt = now;
    if (!state.vmSafeMode || lastActionAt == null) {
      return false;
    }
    if (now.difference(lastActionAt) < const Duration(seconds: 2)) {
      state = state.copyWith(
        errorMessage:
            'VM safe mode is slowing rapid connect/disconnect attempts to protect routing.',
      );
      return true;
    }
    return false;
  }

  void _engageKillSwitch(String reason) {
    _ref.read(networkLockProvider.notifier).engage(reason);
    if (!mounted) {
      return;
    }
    state = state.copyWith(
      networkLockActive: true,
      networkLockReason: reason,
    );
  }

  List<VpnProtocol> _protocolCandidates(
    VpnProtocol preferred,
    List<VpnProtocol> supported,
  ) {
    final available = vpnProtocolPriority
        .where((protocol) => supported.contains(protocol))
        .toList(growable: false);
    if (preferred == VpnProtocol.auto) {
      return available;
    }
    if (available.contains(preferred)) {
      return <VpnProtocol>[
        preferred,
        ...available.where((protocol) => protocol != preferred),
      ];
    }
    return <VpnProtocol>[preferred];
  }

  Future<List<ServerRegion>> _loadServersForRecovery() async {
    try {
      return await _ref.read(apiClientProvider).fetchServers(
            forceRefresh: false,
            allowWhenLocked: true,
          );
    } catch (_) {
      return const <ServerRegion>[];
    }
  }

  void _recordServerFailure(String? serverId) {
    if (serverId == null || serverId.isEmpty) {
      return;
    }
    _serverFailureCounts.update(serverId, (value) => value + 1,
        ifAbsent: () => 1);
  }

  ServerRegion? _selectFailoverServer(List<ServerRegion> servers) {
    final currentId = state.selectedServerId;
    if (currentId == null || currentId.isEmpty || servers.isEmpty) {
      return null;
    }
    final failureCount = _serverFailureCounts[currentId] ?? 0;
    if (failureCount < 2) {
      return null;
    }
    ServerRegion? current;
    for (final server in servers) {
      if (server.id == currentId) {
        current = server;
        break;
      }
    }
    if (current == null) {
      return null;
    }
    final activeServer = current;
    final regionKey = _serverRegionKey(activeServer);
    final candidate = servers.firstWhere(
      (server) =>
          server.id != activeServer.id && _serverRegionKey(server) == regionKey,
      orElse: () => const ServerRegion(id: '', name: ''),
    );
    return candidate.id.isEmpty ? null : candidate;
  }

  String _serverRegionKey(ServerRegion server) {
    final country = server.country?.trim().toLowerCase();
    if (country != null && country.isNotEmpty) {
      return country;
    }
    final city = server.city?.trim().toLowerCase();
    if (city != null && city.isNotEmpty) {
      return city;
    }
    final name = server.name.trim().toLowerCase();
    return name.split(',').first.trim();
  }

  Map<String, DiagnosticResult> _decodeDiagnosticsHistory(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, DiagnosticResult>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <String, DiagnosticResult>{};
      }
      return <String, DiagnosticResult>{
        for (final item in decoded.whereType<Map>())
          DiagnosticResult.fromJson(Map<String, dynamic>.from(item)).key:
              DiagnosticResult.fromJson(Map<String, dynamic>.from(item)),
      };
    } catch (_) {
      return const <String, DiagnosticResult>{};
    }
  }

  String _encodeDiagnosticsHistory(Map<String, DiagnosticResult> checks) {
    return jsonEncode(<Map<String, Object?>>[
      for (final check in checks.values) check.toJson(),
    ]);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _trafficTimer?.cancel();
    _nativeStatusTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
