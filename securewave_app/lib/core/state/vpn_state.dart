import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/design/app_colors.dart';
import '../logging/app_logger.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_profile.dart';
import '../models/vpn_protocol_catalog.dart';
import '../models/vpn_readiness.dart';
import '../models/vpn_status.dart';
import '../optimization/marlxgb.dart';
import '../services/device_identity.dart';
import '../services/network_path.dart';
import '../services/protocol_selector.dart';
import '../services/secure_storage.dart';
import '../services/tunnel_watchdog_service.dart';
import '../vpn/protocol_capabilities.dart';
import 'vpn_state_machine.dart';
import '../../services/api_client.dart';
import '../services/auth_session.dart';
import '../services/vpn_service.dart';
import 'app_state.dart';
import 'preferences_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.connectPhase,
    this.selectedServerId,
    this.protocol = VpnProtocol.auto,
    this.desiredOn = false,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.sessionTransferredBytes = 0,
    this.lifetimeTransferredBytes = 0,
    this.stabilityScore = 1.0,
    this.errorMessage,
    this.errorKind,
    this.effectiveProtocol,
    this.protocolMessage,
    this.failoverActive = false,
    this.failoverReason,
    this.failoverRegionId,
    this.killSwitchActive = false,
    this.reconnectPending = false,
    this.reconnectReason,
    this.lastProfileFetchAt,
    this.lastProfileFetchOk,
    this.lastTunnelStartAt,
    this.lastTunnelStartOk,
    this.readiness = const VpnReadiness(),
  });

  final VpnStatus status;
  final ConnectPhase? connectPhase;
  final String? selectedServerId;
  final VpnProtocol protocol;
  final bool desiredOn;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final int sessionTransferredBytes;
  final int lifetimeTransferredBytes;
  final double stabilityScore;
  final String? errorMessage;
  final VpnErrorKind? errorKind;
  final VpnProtocol? effectiveProtocol;
  final String? protocolMessage;
  final bool failoverActive;
  final String? failoverReason;
  final String? failoverRegionId;
  final bool killSwitchActive;
  final bool reconnectPending;
  final String? reconnectReason;
  final DateTime? lastProfileFetchAt;
  final bool? lastProfileFetchOk;
  final DateTime? lastTunnelStartAt;
  final bool? lastTunnelStartOk;
  final VpnReadiness readiness;

  VpnState copyWith({
    VpnStatus? status,
    ConnectPhase? connectPhase,
    bool clearConnectPhase = false,
    String? selectedServerId,
    VpnProtocol? protocol,
    bool? desiredOn,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    int? sessionTransferredBytes,
    int? lifetimeTransferredBytes,
    double? stabilityScore,
    String? errorMessage,
    VpnErrorKind? errorKind,
    VpnProtocol? effectiveProtocol,
    String? protocolMessage,
    bool? failoverActive,
    String? failoverReason,
    String? failoverRegionId,
    bool? killSwitchActive,
    bool? reconnectPending,
    String? reconnectReason,
    DateTime? lastProfileFetchAt,
    bool? lastProfileFetchOk,
    DateTime? lastTunnelStartAt,
    bool? lastTunnelStartOk,
    VpnReadiness? readiness,
    bool clearError = false,
    bool clearEffectiveProtocol = false,
    bool clearProtocolMessage = false,
    bool clearFailover = false,
    bool clearKillSwitch = false,
    bool clearReconnect = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      connectPhase:
          clearConnectPhase ? null : (connectPhase ?? this.connectPhase),
      selectedServerId: selectedServerId ?? this.selectedServerId,
      protocol: protocol ?? this.protocol,
      desiredOn: desiredOn ?? this.desiredOn,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      sessionTransferredBytes:
          sessionTransferredBytes ?? this.sessionTransferredBytes,
      lifetimeTransferredBytes:
          lifetimeTransferredBytes ?? this.lifetimeTransferredBytes,
      stabilityScore: stabilityScore ?? this.stabilityScore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      effectiveProtocol: clearEffectiveProtocol
          ? null
          : (effectiveProtocol ?? this.effectiveProtocol),
      protocolMessage: clearProtocolMessage
          ? null
          : (protocolMessage ?? this.protocolMessage),
      failoverActive:
          clearFailover ? false : (failoverActive ?? this.failoverActive),
      failoverReason:
          clearFailover ? null : (failoverReason ?? this.failoverReason),
      failoverRegionId:
          clearFailover ? null : (failoverRegionId ?? this.failoverRegionId),
      killSwitchActive:
          clearKillSwitch ? false : (killSwitchActive ?? this.killSwitchActive),
      reconnectPending:
          clearReconnect ? false : (reconnectPending ?? this.reconnectPending),
      reconnectReason:
          clearReconnect ? null : (reconnectReason ?? this.reconnectReason),
      lastProfileFetchAt: lastProfileFetchAt ?? this.lastProfileFetchAt,
      lastProfileFetchOk: lastProfileFetchOk ?? this.lastProfileFetchOk,
      lastTunnelStartAt: lastTunnelStartAt ?? this.lastTunnelStartAt,
      lastTunnelStartOk: lastTunnelStartOk ?? this.lastTunnelStartOk,
      readiness: readiness ?? this.readiness,
    );
  }
}

class TunnelVerificationResult {
  const TunnelVerificationResult({
    required this.ipBeforeConnection,
    required this.ipAfterConnection,
    required this.tunnelWorking,
    required this.statusAfterVerification,
    this.failureReason,
  });

  final String? ipBeforeConnection;
  final String? ipAfterConnection;
  final bool tunnelWorking;
  final VpnStatus statusAfterVerification;
  final String? failureReason;
}

final vpnStateProvider =
    StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

final vpnStateMachineConfigProvider = Provider<VpnStateMachineConfig>((ref) {
  return const VpnStateMachineConfig();
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  static final Uri _ipInfoIpUri = Uri.parse('https://ipinfo.io/ip');
  static const Set<String> _allowedDesiredOnSources = <String>{
    'connect',
    'disconnect',
  };

  VpnStateNotifier(this._ref, {VpnStateMachineConfig? config})
      : _config = config ?? _ref.read(vpnStateMachineConfigProvider),
        super(VpnState(status: _ref.read(vpnServiceProvider).getStatus())) {
    _ref.listen<bool>(
      preferencesProvider.select((prefs) => prefs.autoConnect),
      (previous, next) {
        if (previous == next || !next) return;
        _safeFireAndForget(
          _attemptAutoConnect(reason: 'preference_enabled'),
          context: 'auto_connect_preference_change',
        );
      },
    );
    _ref.listen<bool>(
      authSessionProvider.select((session) => session.isAuthenticated),
      (previous, next) {
        if (previous == next) return;
        _updateReadiness(
          authenticated: next
              ? VpnReadinessGateState.ready
              : VpnReadinessGateState.notReady,
        );
        if (!next) {
          if (state.desiredOn ||
              state.status == VpnStatus.connected ||
              state.status == VpnStatus.connecting ||
              state.status == VpnStatus.disconnecting) {
            _setDesiredOnInternal(false, source: 'disconnect');
            _safeFireAndForget(
              _requestReconcile(),
              context: 'auth_session_cleared_disconnect',
            );
          }
          return;
        }
        _safeFireAndForget(
          _attemptAutoConnect(reason: 'auth_session_available'),
          context: 'auto_connect_auth_change',
        );
      },
    );
    _safeFireAndForget(_loadProtocol(), context: 'load_protocol');
    _safeFireAndForget(
      _loadLifetimeUsage(),
      context: 'load_lifetime_usage',
    );
    _safeFireAndForget(_syncNativeStatus(), context: 'sync_native_status');
    _safeFireAndForget(
      _attemptAutoConnect(reason: 'startup_initial_check'),
      context: 'auto_connect_init',
    );
  }

  final Ref _ref;
  final VpnStateMachineConfig _config;
  final _predictor = const MarLXGBPredictor();
  final SecureStorage _storage = SecureStorage();
  final List<VpnTransitionRecord> _transitionHistory = <VpnTransitionRecord>[];
  late final TunnelWatchdogService _tunnelWatchdog = TunnelWatchdogService(
    sample: _sampleRuntimeSnapshot,
    onIssue: _handleTunnelWatchdogIssue,
  );

  Timer? _rateTimer;
  int? _lastTrafficRxBytes;
  int? _lastTrafficTxBytes;
  DateTime? _lastTrafficSampleAt;
  bool _trafficPollInFlight = false;
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;
  DateTime? _lastAutoReconnectAt;
  DateTime? _lastConnectRequestedAt;
  DateTime? _lastDisconnectRequestedAt;
  DateTime? _lastDisconnectCompletedAt;
  DateTime? _lastLifetimePersistAt;
  int _lastPersistedLifetimeBytes = 0;

  int _operationCounter = 0;
  _VpnOperation? _activeOperation;
  bool _reconcileRunning = false;
  bool _reconcileRequested = false;
  bool _disposed = false;
  Future<DeviceIdentity>? _deviceIdentityFuture;
  bool _metricsSnapshotInFlight = false;
  DateTime? _lastMetricsSnapshotAt;
  static const Duration _metricsSnapshotThrottle = Duration(seconds: 3);
  DateTime? _lastTrafficProgressAt;
  int _connectedUnresponsiveTicks = 0;
  bool _dataPlaneFailoverInFlight = false;
  DateTime? _lastDataPlaneFailoverAt;
  static const Duration _dataPlaneFailoverCooldown = Duration(minutes: 2);
  static const int _handshakeTimeoutTicks = 8;
  static const int _trafficStagnationTicks = 30;
  static const Duration _actionDebounce = Duration(milliseconds: 450);
  static const Duration _lifetimePersistThrottle = Duration(seconds: 2);
  bool _runtimeRecoveryInFlight = false;
  Future<VpnStatus>? _runtimeDisconnectFuture;
  Future<void>? _safeShutdownFuture;

  @visibleForTesting
  bool get debugHasRateTimer => _rateTimer?.isActive ?? false;

  @visibleForTesting
  bool get debugHasActiveOperation => _activeOperation != null;

  @visibleForTesting
  List<VpnTransitionRecord> get debugTransitionHistory =>
      List.unmodifiable(_transitionHistory);

  List<VpnTransitionRecord> get recentTransitions =>
      List.unmodifiable(_transitionHistory);

  Future<void> _loadProtocol() async {
    final stored = await _storage.getString(SecureStorage.vpnProtocolKey);
    final loadedProtocol = vpnProtocolFromStorage(stored);
    if (!mounted) return;
    final currentProtocol = state.protocol;
    if (currentProtocol != VpnProtocol.auto &&
        loadedProtocol != currentProtocol) {
      AppLogger.info(
        '[VPN_SM] {"event":"protocol_load_skipped","stored":"${loadedProtocol.name}","current":"${currentProtocol.name}","reason":"user_override_or_newer_state"}',
      );
      return;
    }
    state = state.copyWith(
      protocol: loadedProtocol,
      clearEffectiveProtocol: true,
      clearProtocolMessage: true,
    );
    AppLogger.info(
      '[VPN_SM] {"event":"protocol_loaded","protocol":"${state.protocol.name}"}',
    );
  }

  Future<void> _loadLifetimeUsage() async {
    final persisted = await _storage.getInt(SecureStorage.vpnLifetimeUsageKey);
    if (!mounted || _disposed) return;
    final value = persisted == null || persisted < 0 ? 0 : persisted;
    _lastPersistedLifetimeBytes = value;
    state = state.copyWith(lifetimeTransferredBytes: value);
    if (kDebugMode) {
      debugPrint(
        '[VPN_DIAG] {"event":"lifetime_usage_loaded","bytes":$value}',
      );
    }
  }

  Future<void> _syncNativeStatus() async {
    final service = _ref.read(vpnServiceProvider);
    if (service is! ChannelVpnService) return;
    try {
      final next = await service.refreshStatus();
      debugPrint(
        '[VPN_DIAG] _syncNativeStatus result=${next.name} '
        'current=${state.status.name} desiredOn=${state.desiredOn}',
      );
      if (!mounted) return;
      final shouldMirrorIntent =
          next == VpnStatus.connected || next == VpnStatus.connecting;
      if (state.desiredOn != shouldMirrorIntent) {
        state = state.copyWith(
          desiredOn: shouldMirrorIntent,
          clearError: shouldMirrorIntent,
        );
      }
      _transitionTo(
        next,
        trigger: VpnTransitionTrigger.initSync,
        force: true,
      );
      _updateReadiness(
        authenticated: _ref.read(authSessionProvider).isAuthenticated
            ? VpnReadinessGateState.ready
            : VpnReadinessGateState.notReady,
        tunnelUp: next == VpnStatus.connected
            ? VpnReadinessGateState.ready
            : VpnReadinessGateState.notReady,
        clearLastErrorCode:
            next == VpnStatus.connected || next == VpnStatus.disconnected,
      );
      if (next == VpnStatus.connected) {
        _startRateSimulation();
      } else {
        _stopRateSimulation();
      }
    } catch (error, stackTrace) {
      AppLogger.warning('[VPN_SM] {"event":"native_status_sync_failed"}');
      AppLogger.error(
        'Native VPN status sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _attemptAutoConnect({
    required String reason,
  }) async {
    if (!mounted || _disposed) return;
    final prefs = _ref.read(preferencesProvider);
    final session = _ref.read(authSessionProvider);
    if (!prefs.autoConnect || !session.isAuthenticated) return;
    final tokenIssue = session.accessTokenFreshnessIssue(
      minValidity: const Duration(seconds: 60),
    );
    if (tokenIssue != null) {
      AppLogger.warning(
        '[VPN_SM] {"event":"auto_connect_skipped","reason":"auth_token_not_fresh","detail":"$tokenIssue"}',
      );
      return;
    }
    final isActive = state.desiredOn ||
        state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting;
    if (isActive) {
      AppLogger.info(
        '[VPN_SM] {"event":"auto_connect_skipped","status":"${state.status.name}","desiredOn":${state.desiredOn},"reason":"$reason"}',
      );
      return;
    }
    AppLogger.info(
      '[VPN_SM] {"event":"auto_connect_triggered","reason":"$reason"}',
    );
    await connect();
  }

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId, clearFailover: true);
    _safeFireAndForget(
      () async {
        if (serverId != null) {
          await _storage.saveString(SecureStorage.selectedServerKey, serverId);
        } else {
          await _storage.delete(SecureStorage.selectedServerKey);
        }
      }(),
      context: 'persist_server_selection',
    );
  }

  Future<void> switchServer(String? serverId) async {
    final previousServer = state.selectedServerId;
    selectServer(serverId);
    if (serverId == null || serverId == previousServer) {
      return;
    }

    final shouldReconnect = state.desiredOn ||
        state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting;
    if (!shouldReconnect) return;

    AppLogger.info(
      '[VPN_SM] {"event":"server_switch_reconnect","from":"${previousServer ?? ""}","to":"$serverId"}',
    );
    if (state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting) {
      await disconnect();
      if (!mounted || _disposed) return;
    }
    await connect();
  }

  Future<void> selectProtocol(VpnProtocol protocol) async {
    state = state.copyWith(
      protocol: protocol,
      clearEffectiveProtocol: true,
      clearProtocolMessage: true,
    );
    await _storage.saveString(
      SecureStorage.vpnProtocolKey,
      vpnProtocolStorageValue(protocol),
    );
  }

  Future<void> connect() async {
    final now = DateTime.now();
    final connectInFlight = state.status == VpnStatus.connecting ||
        _activeOperation?.action == _VpnOperationAction.connect;
    if (_lastConnectRequestedAt != null &&
        now.difference(_lastConnectRequestedAt!) < _actionDebounce &&
        connectInFlight &&
        state.desiredOn) {
      if (kDebugMode) {
        debugPrint('[VPN_DIAG] connect() debounced');
      }
      return;
    }
    _lastConnectRequestedAt = now;
    if (state.status == VpnStatus.error) {
      _recoverToDisconnected(
        trigger: VpnTransitionTrigger.userConnectRequested,
      );
    }
    if (state.desiredOn &&
        (state.status == VpnStatus.connected ||
            state.status == VpnStatus.connecting ||
            _activeOperation?.action == _VpnOperationAction.connect)) {
      if (kDebugMode) {
        debugPrint('[VPN_DIAG] connect() ignored (already desired on)');
      }
      return;
    }
    if (!_validateRequestedTransition(
      VpnStatus.connecting,
      trigger: VpnTransitionTrigger.userConnectRequested,
      message:
          'Connect requested from ${state.status.name}, but only DISCONNECTED -> CONNECTING is allowed.',
    )) {
      return;
    }
    _setDesiredOnInternal(true, source: 'connect');
    try {
      await _requestReconcile().timeout(_config.connectOperationGuardTimeout);
    } on TimeoutException catch (error, stackTrace) {
      final operationId = _activeOperation?.id;
      _activeOperation?.cancel('connect_guard_timeout');
      _reconcileRequested = false;
      _activeOperation = null;
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.timeout,
        operationId: operationId,
        force: true,
      );
      debugPrint(
          '[VPN_DIAG] connect guard timeout (45s) | preserving desiredOn');
      state = state.copyWith(
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Connect operation timed out while reconciling VPN state.',
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
      );
      _updateStability(success: false);
      _setBusy(false);
      AppLogger.error(
        'VPN connect guard timeout',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> disconnect() async {
    final now = DateTime.now();
    final disconnectInFlight = state.status == VpnStatus.disconnecting ||
        _activeOperation?.action == _VpnOperationAction.disconnect;
    if (_lastDisconnectRequestedAt != null &&
        now.difference(_lastDisconnectRequestedAt!) < _actionDebounce &&
        disconnectInFlight &&
        !state.desiredOn) {
      if (kDebugMode) {
        debugPrint('[VPN_DIAG] disconnect() debounced');
      }
      return;
    }
    _lastDisconnectRequestedAt = now;
    if (state.status == VpnStatus.error) {
      _setDesiredOnInternal(false, source: 'disconnect');
      try {
        await _disconnectRuntime(source: 'error_state_cleanup');
      } catch (error, stackTrace) {
        AppLogger.warning(
          '[VPN_SM] {"event":"error_state_disconnect_cleanup_failed"}',
        );
        AppLogger.error(
          'VPN disconnect cleanup from error state failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _recoverToDisconnected(
        trigger: VpnTransitionTrigger.userDisconnectRequested,
      );
      state = state.copyWith(
        dataRateDown: 0,
        dataRateUp: 0,
        sessionTransferredBytes: 0,
        clearError: true,
        clearKillSwitch: true,
        clearReconnect: true,
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        profileReady: VpnReadinessGateState.unknown,
        clearLastErrorCode: true,
      );
      _stopRateSimulation();
      _setBusy(false);
      _safeFireAndForget(
        _reinitializeControlPlane(reason: 'vpn_disconnected'),
        context: 'reinit_after_error_disconnect',
      );
      _safeFireAndForget(
        _notifyBackendDisconnected(),
        context: 'notify_backend_disconnected_error_recovery',
      );
      return;
    }
    if (_safeShutdownFuture != null && !state.desiredOn) {
      if (kDebugMode) {
        debugPrint(
          '[VPN_DIAG] disconnect() ignored (safe shutdown in progress)',
        );
      }
      return;
    }
    if (!state.desiredOn &&
        (state.status == VpnStatus.disconnected ||
            state.status == VpnStatus.disconnecting ||
            _activeOperation?.action == _VpnOperationAction.disconnect)) {
      if (kDebugMode) {
        debugPrint('[VPN_DIAG] disconnect() ignored (already desired off)');
      }
      return;
    }
    if (!_validateRequestedTransition(
      VpnStatus.disconnecting,
      trigger: VpnTransitionTrigger.userDisconnectRequested,
      message:
          'Disconnect requested from ${state.status.name}, but only CONNECTED -> DISCONNECTING is allowed.',
    )) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[VPN_DIAG] disconnect() requested desiredOn=${state.desiredOn} '
        'status=${state.status.name}',
      );
    }
    _setDesiredOnInternal(false, source: 'disconnect');
    try {
      await _requestReconcile()
          .timeout(_config.disconnectOperationGuardTimeout);
    } on TimeoutException catch (error, stackTrace) {
      final operationId = _activeOperation?.id;
      _activeOperation?.cancel('disconnect_guard_timeout');
      _reconcileRequested = false;
      _activeOperation = null;
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.timeout,
        operationId: operationId,
        force: true,
      );
      debugPrint(
        '[VPN_DIAG] disconnect guard timeout (30s) | preserving desiredOn',
      );
      state = state.copyWith(
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Disconnect operation timed out while reconciling VPN state.',
      );
      _updateStability(success: false);
      _setBusy(false);
      _stopRateSimulation();
      AppLogger.error(
        'VPN disconnect guard timeout',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<TunnelVerificationResult> verifyTunnel() async {
    if (state.status != VpnStatus.disconnected &&
        state.status != VpnStatus.error) {
      const reason =
          'verifyTunnel() requires DISCONNECTED or ERROR state to capture a baseline IP.';
      AppLogger.vpn(
        'VERIFY',
        'SKIPPED',
        fields: <String, Object?>{
          'reason': 'baseline_unavailable',
          'status': state.status.name,
        },
        level: 900,
      );
      return TunnelVerificationResult(
        ipBeforeConnection: null,
        ipAfterConnection: null,
        tunnelWorking: false,
        statusAfterVerification: state.status,
        failureReason: reason,
      );
    }

    try {
      final beforeIp = await _fetchPublicIp();
      AppLogger.vpn(
        'VERIFY',
        'IP_BEFORE',
        fields: <String, Object?>{'ip': beforeIp},
      );

      await connect();

      final afterIp = await _fetchPublicIp();
      final tunnelWorking = beforeIp != afterIp;

      AppLogger.vpn(
        'VERIFY',
        tunnelWorking ? 'RESULT_PASS' : 'RESULT_FAIL',
        fields: <String, Object?>{
          'ip_before': beforeIp,
          'ip_after': afterIp,
          'status': state.status.name,
        },
        level: tunnelWorking ? 500 : 900,
      );

      return TunnelVerificationResult(
        ipBeforeConnection: beforeIp,
        ipAfterConnection: afterIp,
        tunnelWorking: tunnelWorking,
        statusAfterVerification: state.status,
        failureReason: tunnelWorking
            ? null
            : 'Public IP did not change after tunnel connect.',
      );
    } catch (error, stackTrace) {
      AppLogger.vpn(
        'VERIFY',
        'RESULT_ERROR',
        fields: <String, Object?>{
          'status': state.status.name,
          'error': error.toString(),
        },
        level: 1000,
      );
      AppLogger.error(
        'Tunnel verification failed',
        error: error,
        stackTrace: stackTrace,
      );
      return TunnelVerificationResult(
        ipBeforeConnection: null,
        ipAfterConnection: null,
        tunnelWorking: false,
        statusAfterVerification: state.status,
        failureReason: error.toString(),
      );
    }
  }

  Future<void> handleConnectivityChange({required bool hasNetwork}) async {
    debugPrint(
      '[VPN_DIAG] handleConnectivityChange hasNetwork=$hasNetwork '
      'desiredOn=${state.desiredOn} status=${state.status.name}',
    );
    if (!hasNetwork) {
      if (!state.desiredOn) return;
      if (state.status != VpnStatus.connected) return;

      try {
        final config =
            await _storage.getString(SecureStorage.vpnProfileConfigKey) ?? '';
        if (!_hasKillSwitchHooks(config)) return;
      } catch (error, stackTrace) {
        AppLogger.warning(
          '[VPN_SM] {"event":"kill_switch_config_read_failed"}',
        );
        AppLogger.error(
          'Kill-switch connectivity check failed to read cached config',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }

      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.connectivityLost,
      );
      state = state.copyWith(
        killSwitchActive: true,
        clearReconnect: true,
        errorKind: VpnErrorKind.backendUnreachable,
        errorMessage:
            'Network lost while the kill switch is active. Traffic remains blocked until SecureWave reconnects or you disconnect.',
        lastTunnelStartOk: false,
      );
      return;
    }

    if (!state.desiredOn) return;
    if (state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting) {
      return;
    }

    final now = DateTime.now();
    if (_lastAutoReconnectAt != null &&
        now.difference(_lastAutoReconnectAt!) < _config.autoReconnectCooldown) {
      return;
    }
    _lastAutoReconnectAt = now;
    final reconnectReason = state.killSwitchActive
        ? 'Network restored. Reconnecting the protected tunnel.'
        : 'Network restored. Reconnecting the tunnel.';
    _recoverToDisconnected(
      trigger: VpnTransitionTrigger.connectivityRestored,
      scheduleReconnect: true,
      reconnectReason: reconnectReason,
    );
    await _requestReconcile();
  }

  Future<void> handleNetworkPathChange({
    required NetworkPathKind previous,
    required NetworkPathKind current,
  }) async {
    if (!previous.isTransportSwitchTo(current)) {
      return;
    }
    if (!state.desiredOn || state.status != VpnStatus.connected) {
      return;
    }

    AppLogger.vpn(
      'NETWORK',
      'TRANSPORT_SWITCH',
      fields: <String, Object?>{
        'previous': previous.label,
        'current': current.label,
        'status': state.status.name,
      },
      level: 900,
    );
    await _restartTunnelAfterRuntimeChange(
      trigger: VpnTransitionTrigger.networkPathChanged,
      source: 'network_path_change',
      reason:
          'Network changed from ${previous.label} to ${current.label}. Re-establishing the tunnel on the new path.',
    );
  }

  void pauseRateUpdates() {
    _stopRateSimulation();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected && _rateTimer == null) {
      _startRateSimulation();
    }
  }

  Future<void> safeShutdown() async {
    final inFlight = _safeShutdownFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    late final Future<void> future;
    future = _performSafeShutdown().whenComplete(() {
      if (identical(_safeShutdownFuture, future)) {
        _safeShutdownFuture = null;
      }
    });
    _safeShutdownFuture = future;
    await future;
  }

  Future<void> _performSafeShutdown() async {
    if (!mounted || _disposed) return;

    AppLogger.vpn(
      'LIFECYCLE',
      'SAFE_SHUTDOWN',
      fields: <String, Object?>{
        'status': state.status.name,
        'desired_on': state.desiredOn,
      },
      level: 900,
    );

    _runtimeRecoveryInFlight = false;
    final disconnectOpInFlight =
        _activeOperation?.action == _VpnOperationAction.disconnect;
    if (!disconnectOpInFlight) {
      _activeOperation?.cancel('shutdown_requested');
      _activeOperation = null;
    }
    _reconcileRequested = false;
    _reconcileRunning = false;
    _stopTunnelWatchdog();
    _stopRateSimulation();
    if (state.desiredOn) {
      _setDesiredOnInternal(false, source: 'disconnect');
    }

    final service = _ref.read(vpnServiceProvider);
    final shouldDisconnect = state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting ||
        service.getStatus() == VpnStatus.connected;
    if (shouldDisconnect) {
      try {
        await _disconnectRuntime(source: 'safe_shutdown');
      } catch (error, stackTrace) {
        AppLogger.warning(
            '[VPN_SM] {"event":"safe_shutdown_disconnect_failed"}');
        AppLogger.error(
          'VPN safe shutdown disconnect failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (!mounted || _disposed) return;
    _recoverToDisconnected(
      trigger: VpnTransitionTrigger.shutdownRequested,
    );
    state = state.copyWith(
      dataRateDown: 0,
      dataRateUp: 0,
      sessionTransferredBytes: 0,
      clearError: true,
      clearKillSwitch: true,
      clearReconnect: true,
      clearConnectPhase: true,
    );
    _updateReadiness(
      tunnelUp: VpnReadinessGateState.notReady,
      profileReady: VpnReadinessGateState.unknown,
      clearLastErrorCode: true,
    );
    _setBusy(false);
  }

  void _setDesiredOnInternal(bool value, {required String source}) {
    if (!_allowedDesiredOnSources.contains(source)) {
      if (state.desiredOn == value) return;
      AppLogger.warning(
        '[VPN_SM] {"event":"desired_on_mutation_blocked","source":"$source","from":${state.desiredOn},"to":$value}',
      );
      assert(() {
        throw StateError(
          'desiredOn mutation from "$source" is not allowed. '
          'Use connect() or disconnect().',
        );
      }());
      return;
    }
    final previous = state.desiredOn;
    state = state.copyWith(desiredOn: value, clearError: true);
    AppLogger.info(
      '[VPN_SM] {"event":"intent","source":"$source","from":$previous,"to":$value}',
    );
    if (previous && !value && kDebugMode) {
      debugPrint('[VPN_DIAG] desiredOn flipped TRUE→FALSE source=$source');
    }
    if (!value && _activeOperation?.action == _VpnOperationAction.connect) {
      _activeOperation?.cancel('disconnect_requested');
    }
    _reconcileRequested = true;
  }

  Future<void> _requestReconcile() async {
    _reconcileRequested = true;
    if (_reconcileRunning) return;
    _reconcileRunning = true;
    try {
      var iterations = 0;
      while (mounted && !_disposed && _reconcileRequested) {
        iterations += 1;
        if (iterations > _config.maxReconcileIterations) {
          throw StateError(
            'VPN reconcile iteration guard exceeded '
            '(${_config.maxReconcileIterations}).',
          );
        }
        debugPrint(
          '[VPN_DIAG] reconcile loop iteration=$iterations desiredOn=${state.desiredOn} '
          'status=${state.status.name}',
        );
        _reconcileRequested = false;
        await _reconcileStep();
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[VPN_DIAG] reconcile loop EXCEPTION: $error',
      );
      AppLogger.error(
        'VPN reconcile loop failed',
        error: error,
        stackTrace: stackTrace,
      );
      _activeOperation?.cancel('reconcile_failed');
      _activeOperation = null;
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.connectOperationFailed,
        force: true,
      );
      debugPrint('[VPN_DIAG] reconcile loop exception | preserving desiredOn');
      state = state.copyWith(
        isBusy: false,
        errorKind: VpnErrorKind.backendError,
        errorMessage: 'VPN state machine encountered an internal error.',
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
      );
      _reconcileRequested = false;
    } finally {
      _reconcileRunning = false;
      if (mounted && !_disposed && _reconcileRequested) {
        _safeFireAndForget(_requestReconcile(), context: 'reconcile_restart');
      }
    }
  }

  Future<String> _fetchPublicIp() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
      ),
    );
    try {
      final response = await dio.get<String>(_ipInfoIpUri.toString());
      final ip = (response.data ?? '').trim();
      if (ip.isEmpty) {
        throw StateError('ipinfo.io returned an empty IP response.');
      }
      return ip;
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _reinitializeControlPlane({
    required String reason,
  }) async {
    try {
      await _ref.read(apiClientProvider).reinitializeControlPlane(
            reason: reason,
          );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Control-plane reinitialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _recoverToDisconnected({
    required VpnTransitionTrigger trigger,
    bool scheduleReconnect = false,
    String? reconnectReason,
  }) {
    final current = state.status;
    if (current != VpnStatus.disconnected) {
      _transitionTo(
        VpnStatus.disconnected,
        trigger: trigger,
        operationId: _activeOperation?.id,
        force: true,
      );
    }
    if (scheduleReconnect) {
      _lastDisconnectCompletedAt = DateTime.now();
    } else if (current == VpnStatus.error) {
      _lastDisconnectCompletedAt = null;
    }
    state = state.copyWith(
      clearError: true,
      clearKillSwitch: true,
      reconnectPending: scheduleReconnect,
      reconnectReason: scheduleReconnect ? reconnectReason : null,
      clearReconnect: !scheduleReconnect,
    );
  }

  void _startTunnelWatchdog() {
    if (!mounted || _disposed || state.status != VpnStatus.connected) {
      return;
    }
    if (_tunnelWatchdog.isRunning) {
      return;
    }
    _safeFireAndForget(
      _tunnelWatchdog.start(),
      context: 'tunnel_watchdog_start',
    );
  }

  void _stopTunnelWatchdog() {
    if (!_tunnelWatchdog.isRunning) {
      return;
    }
    _safeFireAndForget(
      _tunnelWatchdog.stop(),
      context: 'tunnel_watchdog_stop',
    );
  }

  Future<VpnRuntimeSnapshot?> _sampleRuntimeSnapshot() async {
    final service = _ref.read(vpnServiceProvider);
    if (service is! ChannelVpnService) {
      return null;
    }
    final expectedProtocol = state.effectiveProtocol ?? state.protocol;
    return service.fetchRuntimeSnapshot(expectedProtocol: expectedProtocol);
  }

  Future<void> _handleTunnelWatchdogIssue(TunnelWatchdogIssue issue) async {
    if (!mounted || _disposed || !state.desiredOn) {
      return;
    }

    final snapshot = issue.snapshot;
    final event = switch (issue.type) {
      TunnelWatchdogIssueType.handshakeFailure => 'HANDSHAKE_FAILURE',
      TunnelWatchdogIssueType.serverDisconnect => 'SERVER_DISCONNECT',
      TunnelWatchdogIssueType.interfaceRemoved => 'INTERFACE_REMOVED',
    };

    AppLogger.vpn(
      'WATCHDOG',
      event,
      fields: <String, Object?>{
        'native_status': snapshot.nativeStatus.name,
        'traffic_connected': snapshot.trafficConnected,
        'interface': snapshot.interfaceName ?? '-',
        'reported_protocol': snapshot.reportedProtocol.name,
      },
      level: 900,
    );
    await _restartTunnelAfterRuntimeChange(
      trigger: VpnTransitionTrigger.watchdogRecoveryRequested,
      source: 'watchdog_${issue.type.name}',
      reason: issue.reason,
    );
  }

  Future<void> _restartTunnelAfterRuntimeChange({
    required VpnTransitionTrigger trigger,
    required String source,
    required String reason,
  }) async {
    if (!mounted || _disposed) return;
    if (_runtimeRecoveryInFlight) return;
    if (!state.desiredOn) return;
    if (_activeOperation != null) {
      AppLogger.info(
        '[VPN_SM] {"event":"runtime_recovery_skipped","source":"$source","reason":"operation_in_flight","status":"${state.status.name}"}',
      );
      return;
    }
    if (state.status != VpnStatus.connected &&
        state.status != VpnStatus.disconnected &&
        state.status != VpnStatus.error) {
      return;
    }

    _runtimeRecoveryInFlight = true;
    final service = _ref.read(vpnServiceProvider);
    try {
      AppLogger.warning(
        '[VPN_SM] {"event":"runtime_recovery_requested","source":"$source","status":"${state.status.name}"}',
      );
      _stopTunnelWatchdog();
      _stopRateSimulation();

      final runtimeStatus = await _readRuntimeStatus(service);
      final runtimeNeedsDisconnect = runtimeStatus == VpnStatus.connected ||
          runtimeStatus == VpnStatus.connecting ||
          runtimeStatus == VpnStatus.disconnecting;

      if (state.status == VpnStatus.connected && runtimeNeedsDisconnect) {
        _transitionTo(
          VpnStatus.disconnecting,
          trigger: trigger,
          force: true,
        );
      }

      if (runtimeNeedsDisconnect) {
        try {
          await _disconnectRuntime(source: 'runtime_recovery');
        } catch (error, stackTrace) {
          AppLogger.warning(
            '[VPN_SM] {"event":"runtime_recovery_disconnect_failed","source":"$source"}',
          );
          AppLogger.error(
            'Runtime recovery disconnect failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      if (!mounted || _disposed || !state.desiredOn) {
        return;
      }

      if (!await _runtimeLooksDisconnected(service)) {
        _transitionTo(
          VpnStatus.error,
          trigger: VpnTransitionTrigger.watchdogFailureDetected,
          force: true,
        );
        state = state.copyWith(
          errorKind: VpnErrorKind.backendError,
          errorMessage:
              'Tunnel recovery stopped because the native runtime did not fully disconnect.',
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
          clearReconnect: true,
        );
        _updateReadiness(
          tunnelUp: VpnReadinessGateState.notReady,
          lastErrorCode: 'runtime_recovery_disconnect_incomplete',
        );
        return;
      }

      _recoverToDisconnected(
        trigger: trigger,
        scheduleReconnect: true,
        reconnectReason: reason,
      );
      await _requestReconcile();
    } finally {
      _runtimeRecoveryInFlight = false;
    }
  }

  Future<VpnStatus> _readRuntimeStatus(VpnService service) async {
    if (service is ChannelVpnService) {
      return service.refreshStatus();
    }
    return service.getStatus();
  }

  Future<bool> _runtimeLooksDisconnected(VpnService service) async {
    final runtimeStatus = await _readRuntimeStatus(service);
    return runtimeStatus == VpnStatus.disconnected ||
        runtimeStatus == VpnStatus.error;
  }

  Future<void> _respectReconnectDelay(_VpnOperation op) async {
    final cooldown = _config.reconnectDelayAfterDisconnect;
    if (cooldown <= Duration.zero) return;
    final lastDisconnect = _lastDisconnectCompletedAt;
    if (lastDisconnect == null) return;
    final elapsed = DateTime.now().difference(lastDisconnect);
    if (elapsed >= cooldown) return;
    final remaining = cooldown - elapsed;
    AppLogger.info(
      '[VPN_SM] {"event":"reconnect_backoff","wait_ms":${remaining.inMilliseconds}}',
    );
    await Future<void>.delayed(remaining);
    _throwIfCancelled(op);
  }

  Future<void> _reconcileStep() async {
    if (!mounted) return;
    if (_safeShutdownFuture != null && !state.desiredOn) {
      return;
    }
    debugPrint(
      '[VPN_DIAG] _reconcileStep enter | desiredOn=${state.desiredOn} '
      'status=${state.status.name} activeOp=${_activeOperation?.action.name}',
    );
    if (state.desiredOn) {
      switch (state.status) {
        case VpnStatus.connected:
          return;
        case VpnStatus.connecting:
          if (_activeOperation?.action == _VpnOperationAction.connect) {
            return;
          }
          _transitionTo(
            VpnStatus.error,
            trigger: VpnTransitionTrigger.timeout,
            force: true,
          );
          debugPrint(
            '[VPN_DIAG] connecting stale (no active op) | preserving desiredOn',
          );
          state = state.copyWith(
            errorKind: VpnErrorKind.backendError,
            errorMessage:
                'Connection flow became stale before tunnel initialization.',
            lastTunnelStartAt: DateTime.now(),
            lastTunnelStartOk: false,
          );
          return;
        case VpnStatus.disconnected:
          await _runConnectFlow();
          return;
        case VpnStatus.error:
          return;
        case VpnStatus.disconnecting:
          // Wait for in-flight disconnect operation to settle.
          // If we got stuck in a transitional state without an operation,
          // normalize to disconnected and let reconcile continue.
          if (_activeOperation?.action == _VpnOperationAction.disconnect) {
            return;
          }
          _transitionTo(
            VpnStatus.disconnected,
            trigger: VpnTransitionTrigger.disconnectOperationSucceeded,
          );
          _reconcileRequested = true;
          return;
      }
    } else {
      switch (state.status) {
        case VpnStatus.disconnected:
          if (state.errorMessage != null || state.errorKind != null) {
            state = state.copyWith(clearError: true);
          }
          return;
        case VpnStatus.error:
          return;
        case VpnStatus.connecting:
          _transitionTo(
            VpnStatus.error,
            trigger: VpnTransitionTrigger.disconnectOperationStarted,
          );
          state = state.copyWith(
            errorKind: VpnErrorKind.backendError,
            errorMessage:
                'Disconnect requested while VPN was CONNECTING. Strict state machine requires CONNECTING -> CONNECTED before disconnecting.',
            lastTunnelStartOk: false,
          );
          _stopRateSimulation();
          return;
        case VpnStatus.connected:
          debugPrint(
            '[VPN_DIAG] reconcile: !desiredOn && ${state.status.name} — '
            'triggering disconnect flow. errorKind=${state.errorKind?.name} '
            'errorMessage=${state.errorMessage}',
          );
          await _runDisconnectFlow();
          return;
        case VpnStatus.disconnecting:
          // Wait for in-flight disconnect operation to settle.
          // Avoid busy-looping when disconnecting is already in progress.
          if (_activeOperation?.action == _VpnOperationAction.disconnect) {
            return;
          }
          _transitionTo(
            VpnStatus.disconnected,
            trigger: VpnTransitionTrigger.disconnectOperationSucceeded,
          );
          return;
      }
    }
  }

  bool _allRegionsDown(AsyncValue<List<dynamic>> snapshot) {
    return snapshot.maybeWhen(
      data: (list) =>
          list.isNotEmpty &&
          list.every((item) =>
              (item.regionHealthStatus ?? '').toLowerCase().trim() == 'down'),
      orElse: () => false,
    );
  }

  bool _isServerDown(
    AsyncValue<List<dynamic>> snapshot,
    String? serverId,
  ) {
    if (serverId == null || serverId.isEmpty) return false;
    return snapshot.maybeWhen(
      data: (list) {
        for (final item in list) {
          if (item.id != serverId) continue;
          return (item.regionHealthStatus ?? '').toLowerCase().trim() == 'down';
        }
        return false;
      },
      orElse: () => false,
    );
  }

  Future<bool> _resolveFailoverRegion({
    required VpnProtocol backendProtocol,
    required bool alreadyAttempted,
  }) async {
    if (alreadyAttempted) return false;
    final previous = state.selectedServerId;
    final identity = await _loadDeviceIdentity();
    final resolved = await _ref.read(apiClientProvider).resolveRegion(
          protocol: backendProtocol,
          deviceType: identity.type,
          preferredRegion: previous,
        );
    final nextServer = resolved.selectedRegionId.trim();
    if (nextServer.isEmpty || nextServer == previous) {
      return false;
    }
    state = state.copyWith(
      selectedServerId: nextServer,
      failoverActive: true,
      failoverReason: resolved.reason.isEmpty ? null : resolved.reason,
      failoverRegionId: nextServer,
      clearError: true,
    );
    if (kReleaseMode) {
      AppLogger.warning('[VPN_SM] {"event":"region_failover_resolved"}');
    } else {
      AppLogger.warning(
        '[VPN_SM] {"event":"region_failover_resolved",'
        '"failover_reason":"${resolved.reason}",'
        '"previous_region":"${previous ?? ""}",'
        '"region_selected":"$nextServer"}',
      );
    }
    _safeFireAndForget(
      _storage.saveString(SecureStorage.selectedServerKey, nextServer),
      context: 'persist_failover_selection',
    );
    return true;
  }

  int _healthyRegionCount(AsyncValue<List<dynamic>> snapshot) {
    return snapshot.maybeWhen(
      data: (list) => list.where((item) {
        final health = (item.regionHealthStatus ?? '').toLowerCase().trim();
        return health != 'down';
      }).length,
      orElse: () => 0,
    );
  }

  bool _shouldRetryConnectFailureWithFailover({
    required Object error,
    required bool selectedRegionPinned,
    required bool failoverAttempted,
    required AsyncValue<List<dynamic>> serversSnapshot,
  }) {
    if (selectedRegionPinned || failoverAttempted) return false;
    if (_healthyRegionCount(serversSnapshot) < 2 ||
        _allRegionsDown(serversSnapshot)) {
      return false;
    }
    if (error is TimeoutException) return true;
    final code = _errorCodeFrom(error);
    return code == 'vpn_timeout' ||
        code == 'connect_incomplete' ||
        code == 'vpn_connect_failed' ||
        code == 'vpn_connect_protocol_mismatch';
  }

  Future<Map<String, dynamic>?> _maybeRecoverConnectFailureWithFailover({
    required Object error,
    required _VpnOperation op,
    required VpnProtocol backendProtocol,
    required VpnProtocol effectiveProtocol,
    required bool selectedRegionPinned,
    required bool failoverAttempted,
    required AsyncValue<List<dynamic>> serversSnapshot,
    required VpnService service,
  }) async {
    if (!_shouldRetryConnectFailureWithFailover(
      error: error,
      selectedRegionPinned: selectedRegionPinned,
      failoverAttempted: failoverAttempted,
      serversSnapshot: serversSnapshot,
    )) {
      return null;
    }
    try {
      await _disconnectAfterStaleConnect();
      final resolved = await _resolveFailoverRegion(
        backendProtocol: backendProtocol,
        alreadyAttempted: failoverAttempted,
      );
      if (!resolved) return null;
      AppLogger.warning(
        '[VPN_SM] {"event":"connect_failover_retry","reason":"${_errorCodeFrom(error) ?? error.runtimeType}"}',
      );
      _updateReadiness(profileReady: VpnReadinessGateState.unknown);
      return _resolveVpnProfile(
        op: op,
        protocol: backendProtocol,
        effectiveProtocol: effectiveProtocol,
      );
    } catch (failoverError, stackTrace) {
      AppLogger.warning(
        '[VPN_SM] {"event":"connect_failover_retry_skipped"}',
      );
      AppLogger.error(
        'Connect-time failover recovery failed',
        error: failoverError,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _runConnectFlow() async {
    final op = _beginOperation(_VpnOperationAction.connect);
    _setBusy(true);
    try {
      await _respectReconnectDelay(op);
    } on _VpnOperationCancelled {
      _clearOperation(op);
      _setBusy(false);
      rethrow;
    }
    if (!_transitionTo(
      VpnStatus.connecting,
      trigger: VpnTransitionTrigger.connectOperationStarted,
      operationId: op.id,
    )) {
      _clearOperation(op);
      _setBusy(false);
      return;
    }
    state = state.copyWith(
      clearError: true,
      clearKillSwitch: true,
      clearReconnect: true,
      dataRateDown: 0,
      dataRateUp: 0,
      sessionTransferredBytes: 0,
      lastTunnelStartAt: DateTime.now(),
      lastTunnelStartOk: null,
    );
    _updateReadiness(
      profileReady: VpnReadinessGateState.unknown,
      tunnelUp: VpnReadinessGateState.notReady,
      backendProtocolDisabled: false,
      clearRuntimeHint: true,
      clearLastErrorCode: true,
    );

    try {
      // ── Phase: authenticating ──────────────────────────────────────────
      state = state.copyWith(connectPhase: ConnectPhase.authenticating);
      final authed = _ref.read(authSessionProvider).isAuthenticated;
      _updateReadiness(
        authenticated: authed
            ? VpnReadinessGateState.ready
            : VpnReadinessGateState.notReady,
      );
      if (!authed) {
        throw VpnServiceException(
          'auth_required',
          'Sign in is required before starting a VPN tunnel.',
        );
      }

      // ── Phase: checkingBackend ─────────────────────────────────────────
      state = state.copyWith(connectPhase: ConnectPhase.checkingBackend);
      final api = _ref.read(apiClientProvider);
      try {
        await api.fetchHealth().timeout(const Duration(seconds: 4));
        _updateReadiness(backendReachable: VpnReadinessGateState.ready);
      } catch (_) {
        _updateReadiness(
          backendReachable: VpnReadinessGateState.notReady,
          lastErrorCode: 'healthcheck_failed',
        );
        throw VpnServiceException(
          'backend_unreachable',
          'Backend health check failed. Please verify connectivity and retry.',
        );
      }

      final serversSnapshot = _ref.read(serversProvider);
      if (serversSnapshot.hasValue) {
        final serverCount = serversSnapshot.valueOrNull?.length ?? 0;
        _updateReadiness(
          serverCatalogReady: serverCount > 0
              ? VpnReadinessGateState.ready
              : VpnReadinessGateState.notReady,
        );
      } else {
        try {
          final fetched = await api.fetchServers();
          _updateReadiness(
            serverCatalogReady: fetched.isNotEmpty
                ? VpnReadinessGateState.ready
                : VpnReadinessGateState.notReady,
          );
        } catch (_) {
          _updateReadiness(
            serverCatalogReady: VpnReadinessGateState.notReady,
          );
        }
      }
      if (_allRegionsDown(serversSnapshot)) {
        throw VpnServiceException(
          'no_servers_available',
          'No servers available.',
        );
      }

      // ── Phase: resolvingProtocol ──────────────────────────────────────
      state = state.copyWith(connectPhase: ConnectPhase.resolvingProtocol);
      final service = _ref.read(vpnServiceProvider);
      final selectedProtocol = state.protocol;
      var failoverAttempted = false;
      final selectedRegionPinned =
          (state.selectedServerId ?? '').trim().isNotEmpty;
      VpnProtocolCatalog? protocolCatalog;
      try {
        protocolCatalog = _ref.read(vpnProtocolCatalogProvider).valueOrNull;
        protocolCatalog ??= await _ref
            .read(vpnProtocolCatalogProvider.future)
            .timeout(const Duration(seconds: 4));
      } catch (error, stackTrace) {
        AppLogger.warning(
          '[VPN_SM] {"event":"protocol_catalog_provider_unavailable"}',
        );
        AppLogger.error(
          'VPN protocol catalog provider unavailable during connect',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (protocolCatalog == null) {
        try {
          protocolCatalog = await api
              .fetchVpnProtocols(
                deviceType: ProtocolCapabilityMatrix.currentDeviceType(),
              )
              .timeout(const Duration(seconds: 4));
        } catch (error, stackTrace) {
          AppLogger.warning(
            '[VPN_SM] {"event":"protocol_catalog_fetch_skipped"}',
          );
          AppLogger.error(
            'VPN protocol catalog fetch skipped during connect',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      final capabilities = await service.getCapabilities();
      final plan = const ProtocolSelector().resolve(
        selected: selectedProtocol,
        capabilities: capabilities,
        catalog: protocolCatalog,
      );
      debugPrint(
        '[VPN_DEBUG] protocol selected=${selectedProtocol.name} '
        'effective=${plan.effective.name} backend=${plan.backendProtocol.name} '
        'connectable=${plan.isConnectable} '
        'warning=${plan.warning ?? "-"} error=${plan.error ?? "-"} '
        'caps(wg=${capabilities.wireGuard},ovpn=${capabilities.openVpn},ikev2=${capabilities.ikev2})',
      );
      AppLogger.info(
        '[VPN_SM] {"event":"protocol_resolved",'
        '"selected":"${plan.selected.name}",'
        '"effective":"${plan.effective.name}",'
        '"connectable":${plan.isConnectable},'
        '"runtime_blocked":${plan.runtimeBlocked},'
        '"backend_blocked":${plan.backendBlocked}'
        '${plan.warning != null ? ',"warning":"${plan.warning}"' : ''}'
        '${plan.error != null ? ',"error":"${plan.error}"' : ''}}',
      );
      if (!plan.isConnectable) {
        final runtimeBlocked = plan.runtimeBlocked;
        _updateReadiness(
          runtimeReady: runtimeBlocked
              ? VpnReadinessGateState.notReady
              : VpnReadinessGateState.ready,
          backendProtocolDisabled: plan.backendBlocked,
          runtimeHint: runtimeBlocked ? plan.error : null,
          clearRuntimeHint: !runtimeBlocked,
          lastErrorCode:
              runtimeBlocked ? 'runtime_not_ready' : 'backend_protocol_blocked',
        );
        throw VpnServiceException(
          'protocol_unavailable',
          plan.error ??
              'No supported VPN runtime is available for this protocol.',
        );
      }
      _updateReadiness(
        runtimeReady: VpnReadinessGateState.ready,
        backendProtocolDisabled: false,
        clearRuntimeHint: true,
        clearLastErrorCode: true,
      );
      state = state.copyWith(
        effectiveProtocol: plan.effective,
        protocolMessage: plan.warning,
        clearProtocolMessage: plan.warning == null,
      );

      if (_isServerDown(serversSnapshot, state.selectedServerId)) {
        throw VpnServiceException(
          'region_down',
          'Selected region is offline. Choose another server.',
        );
      }

      // ── Phase: fetchingProfile ───────────────────────────────────────
      state = state.copyWith(connectPhase: ConnectPhase.fetchingProfile);
      late Map<String, dynamic> profile;
      try {
        profile = await _resolveVpnProfile(
          op: op,
          protocol: plan.backendProtocol,
          effectiveProtocol: plan.effective,
        );
      } catch (error) {
        if (!selectedRegionPinned &&
            !failoverAttempted &&
            _isRegionDownApiError(error)) {
          final resolved = await _resolveFailoverRegion(
            backendProtocol: plan.backendProtocol,
            alreadyAttempted: failoverAttempted,
          );
          failoverAttempted = resolved;
          if (!resolved) rethrow;
          profile = await _resolveVpnProfile(
            op: op,
            protocol: plan.backendProtocol,
            effectiveProtocol: plan.effective,
          );
        } else {
          rethrow;
        }
      }
      _updateReadiness(profileReady: VpnReadinessGateState.ready);

      // ── Phase: establishingTunnel ──────────────────────────────────────
      state = state.copyWith(connectPhase: ConnectPhase.establishingTunnel);
      late final VpnStatus nextStatus;
      while (true) {
        _throwIfCancelled(op);
        try {
          nextStatus = await service
              .connect(protocol: plan.effective, profile: profile)
              .timeout(_config.connectTimeout, onTimeout: () {
            op.cancel('runtime_connect_timeout');
            throw TimeoutException(
              'Runtime connect exceeded ${_config.connectTimeout.inSeconds}s.',
            );
          });
          break;
        } on TimeoutException catch (error) {
          final recoveredProfile =
              await _maybeRecoverConnectFailureWithFailover(
            error: error,
            op: op,
            backendProtocol: plan.backendProtocol,
            effectiveProtocol: plan.effective,
            selectedRegionPinned: selectedRegionPinned,
            failoverAttempted: failoverAttempted,
            serversSnapshot: serversSnapshot,
            service: service,
          );
          if (recoveredProfile == null) rethrow;
          failoverAttempted = true;
          profile = recoveredProfile;
        } catch (error) {
          final recoveredProfile =
              await _maybeRecoverConnectFailureWithFailover(
            error: error,
            op: op,
            backendProtocol: plan.backendProtocol,
            effectiveProtocol: plan.effective,
            selectedRegionPinned: selectedRegionPinned,
            failoverAttempted: failoverAttempted,
            serversSnapshot: serversSnapshot,
            service: service,
          );
          if (recoveredProfile == null) rethrow;
          failoverAttempted = true;
          profile = recoveredProfile;
        }
      }
      _throwIfCancelled(op);

      // ── Clear phase on completion ───────────────────────────────────
      state = state.copyWith(clearConnectPhase: true);

      if (nextStatus == VpnStatus.connected && !state.desiredOn) {
        await _disconnectAfterStaleConnect();
        _transitionTo(
          VpnStatus.error,
          trigger: VpnTransitionTrigger.connectOperationCancelled,
          operationId: op.id,
        );
        state = state.copyWith(
          errorKind: VpnErrorKind.backendError,
          errorMessage:
              'Connect completed after cancellation request. State moved to ERROR to preserve strict ordering.',
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
        );
        _updateReadiness(tunnelUp: VpnReadinessGateState.notReady);
        return;
      }

      if (nextStatus != VpnStatus.connected) {
        throw VpnServiceException(
          'connect_incomplete',
          'VPN tunnel did not reach connected state.',
        );
      }

      _transitionTo(
        nextStatus,
        trigger: VpnTransitionTrigger.connectOperationSucceeded,
        operationId: op.id,
        force: nextStatus == VpnStatus.connected &&
            state.status == VpnStatus.connected,
      );
      if (nextStatus == VpnStatus.connected) {
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: true,
          clearFailover: !failoverAttempted,
          clearKillSwitch: true,
          clearReconnect: true,
        );
        _updateReadiness(tunnelUp: VpnReadinessGateState.ready);
        await _reinitializeControlPlane(reason: 'vpn_connected');
        debugPrint(
          '[VPN_VERIFY] connected '
          'server=${state.selectedServerId} '
          'protocol=${plan.effective.name} '
          'backend=${plan.backendProtocol.name}',
        );
        _safeFireAndForget(
          _notifyBackendConnected(protocol: plan.effective),
          context: 'notify_backend_connected',
        );
        _updateStability(success: true);
        _startRateSimulation();
        _safeFireAndForget(
          _captureMetricsSnapshot(event: 'connect_success', operationId: op.id),
          context: 'metrics_connect_success',
        );
      } else {
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
        );
        _updateReadiness(tunnelUp: VpnReadinessGateState.notReady);
        _stopRateSimulation();
      }
    } on _VpnOperationCancelled catch (e) {
      debugPrint('[VPN_DIAG] connect op CANCELLED: ${e.reason}');
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.connectOperationCancelled,
        operationId: op.id,
      );
      state = state.copyWith(
        clearConnectPhase: true,
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Connect operation was cancelled. Strict state machine moved the tunnel to ERROR.',
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
        clearReconnect: true,
      );
      _updateReadiness(tunnelUp: VpnReadinessGateState.notReady);
    } on TimeoutException catch (error, stackTrace) {
      debugPrint(
        '[VPN_DIAG] runtime connect timeout (25s) | preserving desiredOn',
      );
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.timeout,
        operationId: op.id,
      );
      state = state.copyWith(
        clearConnectPhase: true,
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Connection timed out — the tunnel could not complete the handshake. Check your network and retry.',
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
        clearReconnect: true,
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        lastErrorCode: 'connect_timeout',
      );
      _updateStability(success: false);
      AppLogger.error('VPN connect timed out',
          error: error, stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint(
        '[VPN_DIAG] connect flow exception | preserving desiredOn: '
        '${error.runtimeType}: $error',
      );
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.connectOperationFailed,
        operationId: op.id,
      );
      final classified = _classifyVpnError(error);
      final errorCode = _errorCodeFrom(error);
      final backendProtocolDisabled = _isBackendProtocolDisabledCode(errorCode);
      final runtimeBlocked =
          classified.kind == VpnErrorKind.protocolUnavailable &&
              state.readiness.runtimeReady == VpnReadinessGateState.notReady;
      debugPrint(
        '[VPN_DEBUG] connect failure kind=${classified.kind.name} '
        'message=${classified.message} raw=${error.runtimeType}: $error',
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        backendProtocolDisabled: backendProtocolDisabled,
        lastErrorCode: errorCode,
        runtimeHint: runtimeBlocked ? classified.message : null,
        clearRuntimeHint: !runtimeBlocked,
      );
      state = state.copyWith(
        clearConnectPhase: true,
        errorMessage: classified.message,
        errorKind: classified.kind,
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
        clearReconnect: true,
      );
      _updateStability(success: false);
      AppLogger.error('VPN connect failed',
          error: error, stackTrace: stackTrace);
      _safeFireAndForget(
        _captureMetricsSnapshot(event: 'connect_failure', operationId: op.id),
        context: 'metrics_connect_failure',
      );
    } finally {
      debugPrint(
        '[VPN_DIAG] _runConnectFlow finally | desiredOn=${state.desiredOn} '
        'status=${state.status.name}',
      );
      _clearOperation(op);
      _setBusy(_activeOperation != null);
    }
  }

  Future<void> _runDisconnectFlow() async {
    final op = _beginOperation(_VpnOperationAction.disconnect);
    _setBusy(true);
    if (!_transitionTo(
      VpnStatus.disconnecting,
      trigger: VpnTransitionTrigger.disconnectOperationStarted,
      operationId: op.id,
    )) {
      _clearOperation(op);
      _setBusy(false);
      return;
    }

    try {
      final nextStatus = await _disconnectRuntime(
        source: 'state_machine_disconnect',
        onTimeout: () {
          op.cancel('runtime_disconnect_timeout');
        },
      );
      final normalizedStatus = nextStatus == VpnStatus.disconnected
          ? VpnStatus.disconnected
          : VpnStatus.error;
      _transitionTo(
        normalizedStatus,
        trigger: VpnTransitionTrigger.disconnectOperationSucceeded,
        operationId: op.id,
      );
      _stopRateSimulation();
      state = state.copyWith(
        dataRateDown: 0,
        dataRateUp: 0,
        sessionTransferredBytes: 0,
        clearError: true,
        clearKillSwitch: true,
        clearReconnect: true,
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        profileReady: VpnReadinessGateState.unknown,
        clearLastErrorCode: true,
      );
      _updateStability(success: true);
      await _reinitializeControlPlane(reason: 'vpn_disconnected');
      await _notifyBackendDisconnected();
      _safeFireAndForget(
        _captureMetricsSnapshot(
            event: 'disconnect_success', operationId: op.id),
        context: 'metrics_disconnect_success',
      );
    } on TimeoutException catch (error, stackTrace) {
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.timeout,
        operationId: op.id,
      );
      state = state.copyWith(
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Disconnect timed out. Strict state machine moved the tunnel to ERROR.',
        dataRateDown: 0,
        dataRateUp: 0,
        sessionTransferredBytes: 0,
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        profileReady: VpnReadinessGateState.unknown,
        lastErrorCode: 'disconnect_timeout',
      );
      _stopRateSimulation();
      _safeFireAndForget(
        _notifyBackendDisconnected(),
        context: 'notify_backend_disconnected_timeout',
      );
      _updateStability(success: false);
      AppLogger.error(
        'VPN disconnect timed out',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      _transitionTo(
        VpnStatus.error,
        trigger: VpnTransitionTrigger.disconnectOperationFailed,
        operationId: op.id,
      );
      final classified = _classifyVpnError(error);
      state = state.copyWith(
        errorMessage: classified.message,
        errorKind: classified.kind,
        dataRateDown: 0,
        dataRateUp: 0,
        sessionTransferredBytes: 0,
      );
      _updateReadiness(
        tunnelUp: VpnReadinessGateState.notReady,
        profileReady: VpnReadinessGateState.unknown,
        lastErrorCode: _errorCodeFrom(error),
      );
      _stopRateSimulation();
      _safeFireAndForget(
        _notifyBackendDisconnected(),
        context: 'notify_backend_disconnected_failure',
      );
      _updateStability(success: false);
      AppLogger.error(
        'VPN disconnect failed',
        error: error,
        stackTrace: stackTrace,
      );
      _safeFireAndForget(
        _captureMetricsSnapshot(
            event: 'disconnect_failure', operationId: op.id),
        context: 'metrics_disconnect_failure',
      );
    } finally {
      _clearOperation(op);
      _setBusy(_activeOperation != null);
    }
  }

  _VpnOperation _beginOperation(_VpnOperationAction action) {
    _operationCounter += 1;
    final op = _VpnOperation(id: _operationCounter, action: action);
    _activeOperation?.cancel('superseded');
    _activeOperation = op;
    AppLogger.info(
      '[VPN_SM] {"event":"operation_start","id":${op.id},"action":"${op.action.name}"}',
    );
    return op;
  }

  void _clearOperation(_VpnOperation op) {
    if (_activeOperation?.id != op.id) return;
    _activeOperation = null;
    AppLogger.info(
      '[VPN_SM] {"event":"operation_end","id":${op.id},"action":"${op.action.name}"}',
    );
  }

  void _throwIfCancelled(_VpnOperation op) {
    if (op.cancelled) {
      throw _VpnOperationCancelled(op.cancelReason ?? 'cancelled');
    }
    if (!state.desiredOn && op.action == _VpnOperationAction.connect) {
      op.cancel('desired_off');
      throw _VpnOperationCancelled('desired_off');
    }
  }

  Future<Map<String, dynamic>> _resolveVpnProfile({
    required _VpnOperation op,
    required VpnProtocol protocol,
    required VpnProtocol effectiveProtocol,
  }) async {
    _throwIfCancelled(op);
    final api = _ref.read(apiClientProvider);
    final identity = await _loadDeviceIdentity();
    _throwIfCancelled(op);
    final deviceId = await _storage.getInt(SecureStorage.vpnDeviceIdKey);
    _throwIfCancelled(op);

    Future<VpnProfile> fetchProfile({required int? requestedDeviceId}) {
      return api
          .fetchVpnProfile(
            deviceId: requestedDeviceId,
            deviceName: identity.name,
            deviceType: identity.type,
            protocol: protocol,
            serverId: state.selectedServerId,
            cancelToken: op.profileCancelToken,
          )
          .timeout(_config.profileFetchTimeout);
    }

    String? apiErrorCode(DioException error) {
      final data = error.response?.data;
      if (data is! Map) return null;
      final payload = data['error'];
      if (payload is! Map) return null;
      final code = payload['code']?.toString().trim().toLowerCase();
      if (code == null || code.isEmpty) return null;
      return code;
    }

    try {
      VpnProfile profile;
      try {
        profile = await fetchProfile(requestedDeviceId: deviceId);
      } on DioException catch (error) {
        final code = apiErrorCode(error);
        final staleCachedDevice =
            deviceId != null && code == 'device_not_found';
        final staleSelectedServer = (state.selectedServerId ?? '').isNotEmpty &&
            (code == 'server_not_found' || code == 'region_down');
        final recoveredDeviceId = _isDeviceLimitCode(code)
            ? await _recoverSingleDeviceSlotId(
                api: api,
                identity: identity,
                requestedDeviceId: deviceId,
              )
            : null;
        if (staleCachedDevice) {
          AppLogger.warning(
            '[VPN_SM] {"event":"profile_retry_without_cached_device","device_id":$deviceId}',
          );
          await _storage.delete(SecureStorage.vpnDeviceIdKey);
          _throwIfCancelled(op);
          profile = await fetchProfile(requestedDeviceId: null);
        } else if (recoveredDeviceId != null && recoveredDeviceId != deviceId) {
          AppLogger.warning(
            '[VPN_SM] {"event":"profile_retry_with_recovered_device_id","device_id":$recoveredDeviceId}',
          );
          await _storage.saveInt(
            SecureStorage.vpnDeviceIdKey,
            recoveredDeviceId,
          );
          _throwIfCancelled(op);
          profile = await fetchProfile(requestedDeviceId: recoveredDeviceId);
        } else if (staleSelectedServer) {
          final staleServerId = state.selectedServerId;
          AppLogger.warning(
            '[VPN_SM] {"event":"profile_retry_without_stale_server","server_id":"${staleServerId ?? ""}","code":"$code"}',
          );
          state = state.copyWith(selectedServerId: null, clearFailover: true);
          await _storage.delete(SecureStorage.selectedServerKey);
          _throwIfCancelled(op);
          profile = await fetchProfile(requestedDeviceId: deviceId);
        } else {
          rethrow;
        }
      }
      _throwIfCancelled(op);
      if (!mounted) {
        throw _VpnOperationCancelled('not_mounted');
      }

      state = state.copyWith(
        lastProfileFetchAt: DateTime.now(),
        lastProfileFetchOk: true,
        selectedServerId: profile.serverId.trim().isEmpty
            ? state.selectedServerId
            : profile.serverId,
      );
      _updateReadiness(
        profileReady: VpnReadinessGateState.ready,
        clearLastErrorCode: true,
      );

      if (profile.deviceId > 0) {
        await _storage.saveInt(SecureStorage.vpnDeviceIdKey, profile.deviceId);
      }
      if (profile.expiresAt != null) {
        await _storage.saveString(
          SecureStorage.vpnProfileExpiresAtKey,
          profile.expiresAt!.toIso8601String(),
        );
      }
      if (!profile.peerRegistered && profile.registrationStatus != null) {
        AppLogger.warning('Peer registration: ${profile.registrationStatus}');
      }

      final nativeProfile =
          Map<String, dynamic>.from(profile.toNativeProfile());
      nativeProfile['server_id'] = profile.serverId;
      await _validateProfileForProtocol(
        protocol: effectiveProtocol,
        profile: profile,
        nativeProfile: nativeProfile,
      );
      _throwIfCancelled(op);

      return nativeProfile;
    } catch (error, stackTrace) {
      if (error is _VpnOperationCancelled ||
          (error is DioException && CancelToken.isCancel(error))) {
        rethrow;
      }
      if (mounted) {
        state = state.copyWith(
          lastProfileFetchAt: DateTime.now(),
          lastProfileFetchOk: false,
        );
      }
      _updateReadiness(
        profileReady: VpnReadinessGateState.notReady,
        lastErrorCode: _errorCodeFrom(error) ?? 'profile_fetch_failed',
      );

      AppLogger.warning(
        '[VPN_SM] {"event":"profile_fetch_failed","protocol":"${effectiveProtocol.name}","fallback":"disabled"}',
      );
      AppLogger.error(
        'VPN profile fetch failed (no local fallback allowed)',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _validateProfileForProtocol({
    required VpnProtocol protocol,
    required VpnProfile profile,
    required Map<String, dynamic> nativeProfile,
  }) async {
    switch (protocol) {
      case VpnProtocol.auto:
        throw StateError('VPN profile protocol is unresolved.');
      case VpnProtocol.wireGuard:
        final configText = (profile.wireguardConfig ??
                nativeProfile['wireguard_config']?.toString() ??
                '')
            .trim();
        if (configText.isEmpty) {
          throw StateError('VPN profile missing WireGuard configuration.');
        }
        final canonicalConfig = _canonicalizeWireGuardConfig(configText);
        await _validateWireGuardConfig(canonicalConfig);
        nativeProfile['wireguard_config'] = canonicalConfig;
        await _storage.saveString(
            SecureStorage.vpnProfileConfigKey, canonicalConfig);
        break;
      case VpnProtocol.openVpn:
        final configText =
            (nativeProfile['ovpn_config']?.toString() ?? '').trim();
        if (configText.isEmpty) {
          throw StateError(
            'VPN profile missing OpenVPN configuration (ovpn_config).',
          );
        }
        break;
      case VpnProtocol.ikev2:
        final server = (nativeProfile['server']?.toString() ?? '').trim();
        if (server.isEmpty) {
          throw StateError('VPN profile missing IKEv2 server endpoint.');
        }
        final authMethod =
            (nativeProfile['auth_method']?.toString() ?? 'eap-mschapv2')
                .trim()
                .toLowerCase();
        if (authMethod == 'eap-mschapv2') {
          final username = (nativeProfile['username']?.toString() ?? '').trim();
          final password = (nativeProfile['password']?.toString() ?? '').trim();
          if (username.isEmpty || password.isEmpty) {
            throw StateError(
              'VPN profile missing IKEv2 user credentials (username/password).',
            );
          }
        } else if (authMethod == 'eap-tls') {
          final caCert =
              (nativeProfile['ca_cert_pem']?.toString() ?? '').trim();
          final pkcs12 =
              (nativeProfile['client_pkcs12_base64']?.toString() ?? '').trim();
          if (caCert.isEmpty || pkcs12.isEmpty) {
            throw StateError(
              'VPN profile missing IKEv2 certificate material (ca_cert_pem/client_pkcs12_base64).',
            );
          }
        }
        break;
    }
  }

  Future<void> _validateWireGuardConfig(String config) async {
    Map<String, Object?> result;
    if (config.length > 4096) {
      result = await compute(_validateWireGuardConfigInIsolate, config);
    } else {
      result = _validateWireGuardConfigInIsolate(config);
    }
    final valid = result['valid'] == true;
    if (!valid) {
      final reason = result['reason']?.toString() ?? 'invalid configuration';
      throw StateError('Invalid WireGuard configuration: $reason');
    }
  }

  String _canonicalizeWireGuardConfig(String rawConfig) {
    final lines =
        rawConfig.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final interfaceLines = <String>[];
    final peerLines = <String>[];
    var inInterface = false;
    var inPeer = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower == '[interface]') {
        inInterface = true;
        inPeer = false;
        continue;
      }
      if (lower == '[peer]') {
        inInterface = false;
        inPeer = true;
        continue;
      }
      if (inInterface) {
        interfaceLines.add(line);
      } else if (inPeer) {
        peerLines.add(line);
      }
    }

    final hasDns =
        interfaceLines.any((line) => line.toLowerCase().startsWith('dns'));
    if (!hasDns) {
      interfaceLines.add('DNS = 1.1.1.1');
    }
    final hasAllowedIps =
        peerLines.any((line) => line.toLowerCase().startsWith('allowedips'));
    if (!hasAllowedIps) {
      peerLines.add('AllowedIPs = 0.0.0.0/0');
    }
    final hasPersistentKeepalive = peerLines.any(
      (line) => line.toLowerCase().startsWith('persistentkeepalive'),
    );
    if (!hasPersistentKeepalive) {
      peerLines.add('PersistentKeepalive = 25');
    }

    final normalized = <String>[
      '[Interface]',
      ...interfaceLines,
      '',
      '[Peer]',
      ...peerLines,
      '',
    ];
    return normalized.join('\n');
  }

  Future<DeviceIdentity> _loadDeviceIdentity() {
    final cached = _deviceIdentityFuture;
    if (cached != null) return cached;
    final future = DeviceIdentity.load();
    _deviceIdentityFuture = future;
    return future;
  }

  Future<void> _notifyBackendDisconnected() async {
    try {
      final api = _ref.read(apiClientProvider);
      await api.notifyVpnDisconnected();
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[VPN_SM] {"event":"backend_disconnect_notify_failed"}',
      );
      AppLogger.error(
        'Backend disconnect notification failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _ref.invalidate(userPlanProvider);
    debugPrint('[VPN_VERIFY] userPlanProvider invalidated (disconnect)');
  }

  Future<void> _notifyBackendConnected({required VpnProtocol protocol}) async {
    try {
      final api = _ref.read(apiClientProvider);
      await api.notifyVpnConnected(
        serverId: state.selectedServerId,
        protocol: protocol,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[VPN_SM] {"event":"backend_connect_notify_failed"}',
      );
      AppLogger.error(
        'Backend connect notification failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _ref.invalidate(userPlanProvider);
    debugPrint('[VPN_VERIFY] userPlanProvider invalidated (connect)');
  }

  Future<void> _captureMetricsSnapshot({
    required String event,
    required int operationId,
  }) async {
    final now = DateTime.now();
    if (_metricsSnapshotInFlight) {
      AppLogger.info('[VPN_SM] metrics snapshot skipped (in-flight).');
      return;
    }
    if (_lastMetricsSnapshotAt != null &&
        now.difference(_lastMetricsSnapshotAt!) < _metricsSnapshotThrottle) {
      AppLogger.info('[VPN_SM] metrics snapshot skipped (throttled).');
      return;
    }

    _metricsSnapshotInFlight = true;
    try {
      final snapshot =
          await _ref.read(apiClientProvider).fetchVpnMetricsSnapshot();
      _lastMetricsSnapshotAt = DateTime.now();
      if (snapshot == null || snapshot.isEmpty) {
        debugPrint('[VPN_VERIFY] metrics snapshot empty for event=$event');
        return;
      }
      debugPrint(
        '[VPN_VERIFY] metrics event=$event '
        'keys=${snapshot.keys.toList()} '
        'bytes_sent=${snapshot['bytes_sent']} '
        'bytes_received=${snapshot['bytes_received']} '
        'connected=${snapshot['connected']}',
      );
      final payload = <String, Object?>{
        'event': event,
        'operation_id': operationId,
        'snapshot': snapshot,
      };
      AppLogger.info('[VPN_SM] ${payload.toString()}');
    } finally {
      _metricsSnapshotInFlight = false;
    }
  }

  Future<void> _disconnectAfterStaleConnect() async {
    try {
      await _disconnectRuntime(source: 'stale_connect_cleanup');
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[VPN_SM] {"event":"stale_connect_cleanup_failed"}',
      );
      AppLogger.error(
        'Stale connect cleanup disconnect failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<VpnStatus> _disconnectRuntime({
    required String source,
    VoidCallback? onTimeout,
  }) {
    final inFlight = _runtimeDisconnectFuture;
    if (inFlight != null) {
      if (kDebugMode) {
        debugPrint('[VPN_DIAG] disconnect runtime reused source=$source');
      }
      return inFlight;
    }

    final service = _ref.read(vpnServiceProvider);
    late final Future<VpnStatus> future;
    future = service
        .disconnect()
        .timeout(
          _config.disconnectTimeout,
          onTimeout: () {
            onTimeout?.call();
            throw TimeoutException(
              'Runtime disconnect exceeded '
              '${_config.disconnectTimeout.inSeconds}s.',
            );
          },
        )
        .whenComplete(() {
          if (identical(_runtimeDisconnectFuture, future)) {
            _runtimeDisconnectFuture = null;
          }
        });
    _runtimeDisconnectFuture = future;
    return future;
  }

  bool _transitionTo(
    VpnStatus next, {
    required VpnTransitionTrigger trigger,
    int? operationId,
    bool force = false,
  }) {
    if (!mounted) return false;
    final current = state.status;
    if (current == next) return true;
    if (!force && !VpnStateMachine.canTransition(current, next)) {
      AppLogger.warning(
        '[VPN_SM] {"event":"transition_blocked","from":"${current.name}","to":"${next.name}","trigger":"${trigger.name}","force_requested":$force}',
      );
      _moveToErrorForInvalidTransition(
        current: current,
        requested: next,
        trigger: trigger,
        operationId: operationId ?? (_activeOperation?.id ?? 0),
      );
      return false;
    }
    if (force && !VpnStateMachine.canTransition(current, next)) {
      AppLogger.warning(
        '[VPN_SM] {"event":"transition_forced","from":"${current.name}","to":"${next.name}","trigger":"${trigger.name}"}',
      );
    }
    _recordTransition(
      VpnTransitionRecord(
        from: current,
        to: next,
        trigger: trigger,
        at: DateTime.now(),
        operationId: operationId ?? (_activeOperation?.id ?? 0),
      ),
    );

    if (current == VpnStatus.connected && next != VpnStatus.connected) {
      _stopRateSimulation();
      _stopTunnelWatchdog();
    }
    if (next == VpnStatus.connected) {
      _startRateSimulation();
      _startTunnelWatchdog();
    } else if (next == VpnStatus.disconnected) {
      _lastDisconnectCompletedAt = DateTime.now();
    }
    state = state.copyWith(status: next);
    // ignore: avoid_print — explicit deterministic state trace for diagnostics
    debugPrint(
        'STATE TRANSITION: ${current.name} -> ${next.name} [${trigger.name}] desiredOn=${state.desiredOn}');
    AppLogger.vpn(
      'STATE',
      next.name,
      fields: <String, Object?>{
        'from': current.name,
        'trigger': trigger.name,
        'desired_on': state.desiredOn,
      },
    );
    AppLogger.info(
      '[VPN_SM] {"event":"transition","from":"${current.name}","to":"${next.name}","trigger":"${trigger.name}","operation_id":${operationId ?? (_activeOperation?.id ?? 0)}}',
    );
    return true;
  }

  bool _validateRequestedTransition(
    VpnStatus next, {
    required VpnTransitionTrigger trigger,
    required String message,
  }) {
    if (VpnStateMachine.canTransition(state.status, next) ||
        state.status == next) {
      return true;
    }
    _transitionTo(next, trigger: trigger);
    state = state.copyWith(
      errorKind: VpnErrorKind.backendError,
      errorMessage: message,
    );
    return false;
  }

  void _moveToErrorForInvalidTransition({
    required VpnStatus current,
    required VpnStatus requested,
    required VpnTransitionTrigger trigger,
    required int operationId,
  }) {
    if (!mounted || current == VpnStatus.error) {
      return;
    }
    _recordTransition(
      VpnTransitionRecord(
        from: current,
        to: VpnStatus.error,
        trigger: trigger,
        at: DateTime.now(),
        operationId: operationId,
      ),
    );
    if (current == VpnStatus.connected) {
      _stopRateSimulation();
      _stopTunnelWatchdog();
    }
    state = state.copyWith(
      status: VpnStatus.error,
      errorKind: VpnErrorKind.backendError,
      errorMessage:
          'Invalid VPN transition requested: ${current.name} -> ${requested.name}.',
    );
    AppLogger.vpn(
      'STATE',
      VpnStatus.error.name,
      fields: <String, Object?>{
        'from': current.name,
        'requested': requested.name,
        'trigger': trigger.name,
        'reason': 'invalid_transition',
      },
      level: 900,
    );
    debugPrint(
      'STATE TRANSITION: ${current.name} -> error [invalid:${trigger.name}] desiredOn=${state.desiredOn}',
    );
    AppLogger.error(
      'Invalid VPN transition requested',
      error:
          StateError('Invalid transition ${current.name} -> ${requested.name}'),
    );
  }

  void _recordTransition(VpnTransitionRecord record) {
    _transitionHistory.add(record);
    if (_transitionHistory.length > _config.transitionHistoryLimit) {
      _transitionHistory.removeRange(
        0,
        _transitionHistory.length - _config.transitionHistoryLimit,
      );
    }
  }

  void _setBusy(bool isBusy) {
    if (!mounted || state.isBusy == isBusy) return;
    state = state.copyWith(isBusy: isBusy);
  }

  void _updateReadiness({
    VpnReadinessGateState? backendReachable,
    VpnReadinessGateState? authenticated,
    VpnReadinessGateState? serverCatalogReady,
    VpnReadinessGateState? profileReady,
    VpnReadinessGateState? runtimeReady,
    VpnReadinessGateState? tunnelUp,
    bool? backendProtocolDisabled,
    String? runtimeHint,
    String? lastErrorCode,
    bool clearRuntimeHint = false,
    bool clearLastErrorCode = false,
  }) {
    if (!mounted || _disposed) return;
    state = state.copyWith(
      readiness: state.readiness.copyWith(
        backendReachable: backendReachable,
        authenticated: authenticated,
        serverCatalogReady: serverCatalogReady,
        profileReady: profileReady,
        runtimeReady: runtimeReady,
        tunnelUp: tunnelUp,
        backendProtocolDisabled: backendProtocolDisabled,
        runtimeHint: runtimeHint,
        lastErrorCode: lastErrorCode,
        clearRuntimeHint: clearRuntimeHint,
        clearLastErrorCode: clearLastErrorCode,
      ),
    );
  }

  Future<void> _persistLifetimeUsage(int bytes) async {
    if (bytes < 0) return;
    final now = DateTime.now();
    if (_lastPersistedLifetimeBytes == bytes &&
        _lastLifetimePersistAt != null &&
        now.difference(_lastLifetimePersistAt!) < _lifetimePersistThrottle) {
      return;
    }
    _lastPersistedLifetimeBytes = bytes;
    _lastLifetimePersistAt = now;
    await _storage.saveInt(SecureStorage.vpnLifetimeUsageKey, bytes);
  }

  void _startRateSimulation() {
    _rateTimer?.cancel();
    _rateTimer = null;
    _lastTrafficRxBytes = null;
    _lastTrafficTxBytes = null;
    _lastTrafficSampleAt = null;
    _lastTrafficProgressAt = DateTime.now();
    _connectedUnresponsiveTicks = 0;
    _trafficPollInFlight = false;
    if (!mounted || _disposed) return;
    state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
    _safeFireAndForget(
      _pollTrafficRates(),
      context: 'traffic_poll_initial',
    );
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _safeFireAndForget(
        _pollTrafficRates(),
        context: 'traffic_poll_tick',
      );
    });
  }

  void _stopRateSimulation() {
    _rateTimer?.cancel();
    _rateTimer = null;
    _lastTrafficRxBytes = null;
    _lastTrafficTxBytes = null;
    _lastTrafficSampleAt = null;
    _lastTrafficProgressAt = null;
    _connectedUnresponsiveTicks = 0;
    _dataPlaneFailoverInFlight = false;
    _trafficPollInFlight = false;
  }

  Future<void> _pollTrafficRates() async {
    if (!mounted || _disposed || _trafficPollInFlight) return;
    if (state.status != VpnStatus.connected) return;
    final service = _ref.read(vpnServiceProvider);
    if (service is! ChannelVpnService) return;

    _trafficPollInFlight = true;
    try {
      final sample = await service.fetchTrafficStats();
      if (!mounted || _disposed || state.status != VpnStatus.connected) return;
      if (sample == null || !sample.connected) {
        // On platforms without native traffic stats (Android, Windows, iOS,
        // macOS), fetchTrafficStats always returns null.  This is not an
        // indication of tunnel failure — do not count toward failover.
        if (!service.hasNativeTrafficStats) {
          // No stats available on this platform; skip failover logic.
          return;
        }
        _connectedUnresponsiveTicks += 1;
        _lastTrafficRxBytes = null;
        _lastTrafficTxBytes = null;
        _lastTrafficSampleAt = null;
        state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
        if (_connectedUnresponsiveTicks >= _handshakeTimeoutTicks) {
          await _maybeTriggerDataPlaneFailover(reason: 'handshake_timeout');
        }
        return;
      }
      _connectedUnresponsiveTicks = 0;

      final now = DateTime.now();
      final previousAt = _lastTrafficSampleAt;
      final previousRx = _lastTrafficRxBytes;
      final previousTx = _lastTrafficTxBytes;

      _lastTrafficSampleAt = now;
      _lastTrafficRxBytes = sample.rxBytes;
      _lastTrafficTxBytes = sample.txBytes;

      if (previousAt == null || previousRx == null || previousTx == null) {
        _lastTrafficProgressAt ??= now;
        return;
      }

      final elapsedSeconds = now.difference(previousAt).inMilliseconds / 1000.0;
      if (elapsedSeconds <= 0) return;

      final downBytes = _positiveDelta(sample.rxBytes, previousRx);
      final upBytes = _positiveDelta(sample.txBytes, previousTx);
      final downMbps = (downBytes * 8.0) / elapsedSeconds / 1000000.0;
      final upMbps = (upBytes * 8.0) / elapsedSeconds / 1000000.0;
      final nextSessionBytes =
          state.sessionTransferredBytes + downBytes + upBytes;
      final nextLifetimeBytes =
          state.lifetimeTransferredBytes + downBytes + upBytes;
      if (downBytes > 0 || upBytes > 0) {
        _lastTrafficProgressAt = now;
      } else if (nextSessionBytes > 0) {
        final sinceProgress = now.difference(_lastTrafficProgressAt ?? now);
        if (sinceProgress.inSeconds >= _trafficStagnationTicks) {
          await _maybeTriggerDataPlaneFailover(reason: 'traffic_stagnation');
        }
      }

      state = state.copyWith(
        dataRateDown: downMbps.clamp(0, 5000).toDouble(),
        dataRateUp: upMbps.clamp(0, 5000).toDouble(),
        sessionTransferredBytes: nextSessionBytes,
        lifetimeTransferredBytes: nextLifetimeBytes,
      );
      _safeFireAndForget(
        _persistLifetimeUsage(nextLifetimeBytes),
        context: 'persist_lifetime_usage',
      );
      if (kDebugMode) {
        debugPrint(
          '[VPN_DIAG] {"event":"traffic_tick","connected":${sample.connected},'
          '"iface":"${sample.interfaceName ?? ""}","protocol":"${sample.protocol ?? ""}",'
          '"rx":${sample.rxBytes},"tx":${sample.txBytes},'
          '"delta_rx":$downBytes,"delta_tx":$upBytes,'
          '"down_mbps":${downMbps.toStringAsFixed(3)},'
          '"up_mbps":${upMbps.toStringAsFixed(3)}}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning('[VPN_SM] traffic stats polling failed');
      AppLogger.error(
        'Traffic stats polling failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _trafficPollInFlight = false;
    }
  }

  VpnProtocol _backendProtocolForFailover() {
    final effective = state.effectiveProtocol ?? state.protocol;
    if (effective == VpnProtocol.auto) {
      return VpnProtocol.wireGuard;
    }
    return effective;
  }

  Future<void> _maybeTriggerDataPlaneFailover({
    required String reason,
  }) async {
    if (!mounted || _disposed) return;
    if (_dataPlaneFailoverInFlight) return;
    if (!state.desiredOn || state.status != VpnStatus.connected) return;
    final now = DateTime.now();
    final last = _lastDataPlaneFailoverAt;
    if (last != null && now.difference(last) < _dataPlaneFailoverCooldown) {
      return;
    }
    if (_allRegionsDown(_ref.read(serversProvider))) {
      return;
    }

    final previousRegion = state.selectedServerId;
    _dataPlaneFailoverInFlight = true;
    try {
      final resolved = await _resolveFailoverRegion(
        backendProtocol: _backendProtocolForFailover(),
        alreadyAttempted: false,
      );
      // When no alternate region is available (single-server deployment or all
      // regions returned the same server), fall back to a same-server tunnel
      // restart.  This recovers from a broken tunnel state (e.g. the WireGuard
      // policy route was lost) without requiring a region change.
      _lastDataPlaneFailoverAt = now;
      if (kReleaseMode) {
        AppLogger.warning(
          '[VPN_SM] {"event":"data_plane_failover_triggered",'
          '"region_changed":$resolved}',
        );
      } else {
        final selectedRegion = state.selectedServerId;
        AppLogger.warning(
          '[VPN_SM] {"event":"data_plane_failover_triggered",'
          '"failover_reason":"$reason",'
          '"region_changed":$resolved,'
          '"previous_region":"${previousRegion ?? ""}",'
          '"region_selected":"${selectedRegion ?? ""}"}',
        );
      }
      await _restartTunnelAfterRuntimeChange(
        trigger: VpnTransitionTrigger.watchdogRecoveryRequested,
        source: 'data_plane_failover',
        reason: 'Tunnel health degraded ($reason). Restarting the tunnel.',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Data-plane failover handling failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _dataPlaneFailoverInFlight = false;
      _connectedUnresponsiveTicks = 0;
      _lastTrafficProgressAt = DateTime.now();
    }
  }

  int _positiveDelta(int current, int previous) {
    if (current < 0 || previous < 0) return 0;
    if (current < previous) {
      // Counter reset or interface recreation.
      return 0;
    }
    return current - previous;
  }

  void _updateStability({required bool success}) {
    if (success) {
      _stabilitySuccesses += 1;
    } else {
      _stabilityFailures += 1;
    }
    final score = _predictor.scoreStability(
      successes: _stabilitySuccesses,
      failures: _stabilityFailures,
    );
    state = state.copyWith(stabilityScore: score);
  }

  void _safeFireAndForget(
    Future<void> future, {
    required String context,
  }) {
    unawaited(
      future.catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Unhandled async task failure: $context',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  bool _isRegionDownApiError(Object error) {
    if (error is! DioException) return false;
    final data = error.response?.data;
    String? apiCode;
    if (data is Map && data['error'] is Map) {
      final payload = Map<String, dynamic>.from(data['error'] as Map);
      apiCode = payload['code']?.toString().trim().toLowerCase();
    }
    if (apiCode == 'region_down' || apiCode == 'no_servers_available') {
      return true;
    }
    final status = error.response?.statusCode;
    return status == 409 || status == 503;
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
        '[VPN_SM] {"event":"device_limit_recovery_probe_failed"}',
      );
      AppLogger.error(
        'Device-limit recovery probe failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String? _errorCodeFrom(Object error) {
    if (error is VpnServiceException) {
      final code = error.code.trim().toLowerCase();
      return code.isEmpty ? null : code;
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final payload = Map<String, dynamic>.from(data['error'] as Map);
        final code = payload['code']?.toString().trim().toLowerCase();
        if (code != null && code.isNotEmpty) return code;
      }
    }
    return null;
  }

  bool _isBackendProtocolDisabledCode(String? code) {
    if (code == null || code.isEmpty) return false;
    return code == 'protocol_disabled_server_side' ||
        code == 'unsupported_protocol' ||
        code == 'protocol_not_supported_on_platform' ||
        code == 'protocol_not_supported_on_server' ||
        code == 'protocol_temporarily_unavailable' ||
        code == 'protocol_plan_restricted' ||
        code == 'no_protocol_available' ||
        code == 'openvpn_server_misconfigured' ||
        code == 'ikev2_server_misconfigured' ||
        code == 'openvpn_healthcheck_fail' ||
        code == 'ikev2_healthcheck_fail' ||
        code == 'openvpn_unavailable_region' ||
        code == 'ikev2_unavailable_region' ||
        code == 'ikev2_auth_mode_mismatch_linux' ||
        code == 'credential_provision_failed';
  }

  ({VpnErrorKind kind, String message}) _classifyVpnError(Object error) {
    const includeInternalDetails = !kReleaseMode;
    if (error is TimeoutException) {
      return (
        kind: VpnErrorKind.backendError,
        message:
            'Operation timed out while waiting for the VPN service. Please retry.',
      );
    }
    if (error is VpnServiceException) {
      if (error.code == 'backend_unreachable') {
        return (kind: VpnErrorKind.backendUnreachable, message: error.message);
      }
      if (error.code == 'auth_required') {
        return (kind: VpnErrorKind.auth, message: error.message);
      }
      if (error.code == 'no_servers_available' || error.code == 'region_down') {
        return (kind: VpnErrorKind.backendError, message: error.message);
      }
      if (error.code == 'protocol_unavailable') {
        return (kind: VpnErrorKind.protocolUnavailable, message: error.message);
      }
      if (error.code == 'vpn_permission_required') {
        return (kind: VpnErrorKind.permissionRequired, message: error.message);
      }
      if (error.code == 'vpn_timeout') {
        return (kind: VpnErrorKind.backendError, message: error.message);
      }
      if (error.code == 'vpn_unavailable' ||
          error.code == 'vpn_not_configured') {
        return (kind: VpnErrorKind.nativeUnavailable, message: error.message);
      }
      return (
        kind: VpnErrorKind.unknown,
        message: includeInternalDetails
            ? error.message
            : 'Unable to complete the VPN request right now. Please retry.',
      );
    }
    if (error is StateError) {
      return (
        kind: VpnErrorKind.unknown,
        message: includeInternalDetails
            ? error.message
            : 'Unable to complete the VPN request right now. Please retry.',
      );
    }
    if (error is DioException) {
      String? detail;
      String? apiCode;
      String? apiMessage;
      final data = error.response?.data;
      if (data is Map) {
        if (data['error'] is Map) {
          final payload = Map<String, dynamic>.from(data['error'] as Map);
          apiCode = payload['code']?.toString();
          apiMessage = payload['message']?.toString();
        }
        if (data['detail'] != null) {
          detail = data['detail']?.toString();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        detail = data.trim();
      }
      final normalizedApiCode = (apiCode ?? '').trim().toLowerCase();
      final protocolCodes = <String>{
        'unsupported_protocol',
        'protocol_not_supported_on_platform',
        'protocol_not_supported_on_server',
        'protocol_temporarily_unavailable',
        'protocol_plan_restricted',
        'protocol_disabled_server_side',
        'no_protocol_available',
        'openvpn_server_misconfigured',
        'ikev2_server_misconfigured',
        'openvpn_healthcheck_fail',
        'ikev2_healthcheck_fail',
        'openvpn_unavailable_region',
        'ikev2_unavailable_region',
        'ikev2_auth_mode_mismatch_linux',
        'credential_provision_failed',
      };
      if (protocolCodes.contains(normalizedApiCode)) {
        return (
          kind: VpnErrorKind.protocolUnavailable,
          message: includeInternalDetails &&
                  (apiMessage != null && apiMessage.trim().isNotEmpty)
              ? apiMessage
              : 'Selected protocol is unavailable on this device/account/server.',
        );
      }

      final status = error.response?.statusCode;
      final isNetworkFailure = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.badCertificate;
      if (isNetworkFailure) {
        final host = error.requestOptions.uri.host;
        final target = host.isNotEmpty ? ' ($host)' : '';
        return (
          kind: VpnErrorKind.backendUnreachable,
          message:
              'Backend unreachable$target. The VPN service cannot be reached right now. '
              'Check your internet connection or try again later.',
        );
      }
      if (status == 401 || status == 403) {
        return (
          kind: VpnErrorKind.auth,
          message: includeInternalDetails &&
                  (apiMessage != null && apiMessage.isNotEmpty)
              ? apiMessage
              : includeInternalDetails && detail != null && detail.isNotEmpty
                  ? 'Authentication failed: $detail'
                  : 'Authentication failed. Please sign in again.',
        );
      }
      if (status == 404) {
        return (
          kind: VpnErrorKind.profileNotFound,
          message: includeInternalDetails &&
                  apiMessage != null &&
                  apiMessage.isNotEmpty
              ? 'Profile fetch failed: $apiMessage'
              : includeInternalDetails && detail != null && detail.isNotEmpty
                  ? 'Profile fetch failed: $detail'
                  : 'Profile fetch failed. The server endpoint was not found.',
        );
      }
      if (status != null && status >= 500) {
        return (
          kind: VpnErrorKind.backendError,
          message: includeInternalDetails && detail != null && detail.isNotEmpty
              ? 'Backend error: $detail'
              : 'Backend server error. Please try again in a few minutes.',
        );
      }
      if (status != null) {
        return (
          kind: VpnErrorKind.unknown,
          message: includeInternalDetails && detail != null && detail.isNotEmpty
              ? 'Request failed (HTTP $status): $detail'
              : 'Request failed (HTTP $status).',
        );
      }
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('permission denied') ||
        msg.contains('not authorized') ||
        msg.contains('authentication failed')) {
      return (
        kind: VpnErrorKind.permissionRequired,
        message:
            'Permission required to start the VPN tunnel. Approve the system prompt or run the app with administrator privileges.',
      );
    }
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('connection timed out') ||
        msg.contains('host not found') ||
        msg.contains('network is unreachable') ||
        msg.contains('no address associated') ||
        msg.contains('handshake') ||
        msg.contains('certificate')) {
      return (
        kind: VpnErrorKind.backendUnreachable,
        message:
            'Backend unreachable. The VPN service cannot be reached right now. '
            'Check your internet connection or try again later. '
            'If the problem persists, the backend server may be temporarily offline.',
      );
    }
    if (msg.contains('401') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden')) {
      return (
        kind: VpnErrorKind.auth,
        message: 'Authentication failed. Please sign in again.',
      );
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return (
        kind: VpnErrorKind.profileNotFound,
        message: 'Profile fetch failed. The server endpoint was not found. '
            'Please update the app or contact support.',
      );
    }
    if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
      return (
        kind: VpnErrorKind.backendError,
        message:
            'Backend server error. The VPN service is experiencing issues. '
            'Please try again in a few minutes.',
      );
    }
    return (
      kind: VpnErrorKind.unknown,
      message: 'Unable to complete the VPN request right now. '
          'If this persists, check Diagnostics for details.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _activeOperation?.cancel('dispose');
    _activeOperation = null;
    _stopTunnelWatchdog();
    _rateTimer?.cancel();
    _rateTimer = null;
    super.dispose();
  }
}

enum _VpnOperationAction { connect, disconnect }

class _VpnOperation {
  _VpnOperation({required this.id, required this.action});

  final int id;
  final _VpnOperationAction action;
  final CancelToken profileCancelToken = CancelToken();
  bool cancelled = false;
  String? cancelReason;

  void cancel(String reason) {
    cancelled = true;
    cancelReason = reason;
    if (!profileCancelToken.isCancelled) {
      profileCancelToken.cancel(reason);
    }
  }
}

class _VpnOperationCancelled implements Exception {
  _VpnOperationCancelled(this.reason);

  final String reason;

  @override
  String toString() => '_VpnOperationCancelled($reason)';
}

Map<String, Object?> _validateWireGuardConfigInIsolate(String rawConfig) {
  final lines = rawConfig
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
  if (lines.isEmpty) {
    return const {'valid': false, 'reason': 'configuration is empty'};
  }
  final hasInterface = lines.any((line) => line.toLowerCase() == '[interface]');
  final hasPeer = lines.any((line) => line.toLowerCase() == '[peer]');
  final hasPrivateKey =
      lines.any((line) => line.toLowerCase().startsWith('privatekey'));
  final hasAddress =
      lines.any((line) => line.toLowerCase().startsWith('address'));
  final hasDns = lines.any((line) => line.toLowerCase().startsWith('dns'));
  final hasPublicKey =
      lines.any((line) => line.toLowerCase().startsWith('publickey'));
  final hasEndpoint =
      lines.any((line) => line.toLowerCase().startsWith('endpoint'));
  final hasAllowedIps =
      lines.any((line) => line.toLowerCase().startsWith('allowedips'));
  final hasPersistentKeepalive = lines.any(
    (line) => line.toLowerCase().startsWith('persistentkeepalive'),
  );

  if (!hasInterface) {
    return const {'valid': false, 'reason': 'missing [Interface] section'};
  }
  if (!hasPeer) {
    return const {'valid': false, 'reason': 'missing [Peer] section'};
  }
  if (!hasPrivateKey) {
    return const {'valid': false, 'reason': 'missing PrivateKey'};
  }
  if (!hasAddress) {
    return const {'valid': false, 'reason': 'missing Address'};
  }
  if (!hasDns) {
    return const {'valid': false, 'reason': 'missing DNS'};
  }
  if (!hasPublicKey) {
    return const {'valid': false, 'reason': 'missing PublicKey'};
  }
  if (!hasEndpoint) {
    return const {'valid': false, 'reason': 'missing Endpoint'};
  }
  if (!hasAllowedIps) {
    return const {'valid': false, 'reason': 'missing AllowedIPs'};
  }
  if (!hasPersistentKeepalive) {
    return const {'valid': false, 'reason': 'missing PersistentKeepalive'};
  }

  return const {'valid': true, 'reason': 'ok'};
}

bool _hasKillSwitchHooks(String config) {
  final lower = config.toLowerCase();
  return lower.contains('postup') || lower.contains('postdown');
}

enum VpnErrorKind {
  backendUnreachable,
  auth,
  profileNotFound,
  backendError,
  protocolUnavailable,
  permissionRequired,
  nativeUnavailable,
  unknown,
}

extension VpnStatePresentation on VpnState {
  String? get recoveryHeadline {
    if (killSwitchActive) return 'Kill switch active';
    if (reconnectPending) return 'Reconnecting automatically';
    if (failoverActive) return 'Fallback region active';
    if (errorMessage != null && status == VpnStatus.error) {
      return _errorHeadline();
    }
    return null;
  }

  String? get recoveryMessage {
    if (killSwitchActive) {
      return 'Internet traffic stays blocked until the tunnel reconnects or you disconnect.';
    }
    if (reconnectPending) {
      return reconnectReason ??
          'SecureWave is re-establishing the secure tunnel after a network change.';
    }
    if (failoverActive) {
      final reason = failoverReason?.trim();
      if (reason != null && reason.isNotEmpty) {
        return 'Traffic moved to a fallback region: $reason.';
      }
      return 'Traffic is flowing through a fallback region.';
    }
    return errorMessage;
  }

  /// Human-readable label for the current [ConnectPhase].
  String? get connectPhaseLabel => switch (connectPhase) {
        ConnectPhase.authenticating => 'Authenticating…',
        ConnectPhase.checkingBackend => 'Checking backend…',
        ConnectPhase.resolvingProtocol => 'Resolving protocol…',
        ConnectPhase.fetchingProfile => 'Fetching profile…',
        ConnectPhase.establishingTunnel => 'Establishing tunnel…',
        ConnectPhase.verifyingConnection => 'Verifying connection…',
        null => null,
      };

  String statusText({bool includeEllipsis = false}) {
    if (status == VpnStatus.connecting && connectPhase != null) {
      return connectPhaseLabel!;
    }
    return switch (status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => includeEllipsis ? 'Connecting…' : 'Connecting',
      VpnStatus.disconnecting =>
        includeEllipsis ? 'Disconnecting…' : 'Disconnecting',
      VpnStatus.disconnected => 'Disconnected',
      VpnStatus.error => _errorHeadline(),
    };
  }

  Color get statusColor {
    final backendUnreachable = status == VpnStatus.error &&
        errorKind == VpnErrorKind.backendUnreachable;
    return switch (status) {
      VpnStatus.connected => AppColors.success,
      VpnStatus.connecting => AppColors.secondary,
      VpnStatus.disconnecting => AppColors.secondary,
      VpnStatus.error =>
        backendUnreachable ? AppColors.error : AppColors.warning,
      VpnStatus.disconnected => AppColors.inkSoft,
    };
  }

  IconData get statusIcon {
    final backendUnreachable = status == VpnStatus.error &&
        errorKind == VpnErrorKind.backendUnreachable;
    return switch (status) {
      VpnStatus.connected => Icons.check_circle,
      VpnStatus.connecting => Icons.sync,
      VpnStatus.disconnecting => Icons.sync,
      VpnStatus.error =>
        backendUnreachable ? Icons.cloud_off : Icons.warning_amber_rounded,
      VpnStatus.disconnected => Icons.shield_outlined,
    };
  }

  String _errorHeadline() {
    final protocolUnavailableAllowed =
        readiness.runtimeReady == VpnReadinessGateState.notReady ||
            readiness.backendProtocolDisabled;
    return switch (errorKind) {
      VpnErrorKind.backendUnreachable => 'Server unreachable',
      VpnErrorKind.backendError => 'Server error',
      VpnErrorKind.auth => 'Sign in to continue',
      VpnErrorKind.profileNotFound => 'VPN profile missing',
      VpnErrorKind.protocolUnavailable => protocolUnavailableAllowed
          ? 'Protocol not available'
          : 'Connection failed',
      VpnErrorKind.permissionRequired => 'Permission needed',
      VpnErrorKind.nativeUnavailable => 'VPN runtime missing',
      VpnErrorKind.unknown || null => 'Connection failed',
    };
  }

  /// Actionable recovery hint for the current error kind.
  String? get errorActionHint => switch (errorKind) {
        VpnErrorKind.backendUnreachable =>
          'Check your internet connection or try again in a moment.',
        VpnErrorKind.backendError =>
          'The VPN server returned an error. Try a different server or retry.',
        VpnErrorKind.auth =>
          'Your session expired. Sign in again to reconnect.',
        VpnErrorKind.profileNotFound =>
          'This server has no VPN profile available. Choose another server.',
        VpnErrorKind.protocolUnavailable =>
          'The selected protocol is not supported on this device or server.',
        VpnErrorKind.permissionRequired =>
          'Grant the VPN permission in system settings to connect.',
        VpnErrorKind.nativeUnavailable =>
          'No WireGuard or OpenVPN runtime found. Install the required package.',
        VpnErrorKind.unknown || null => null,
      };
}
