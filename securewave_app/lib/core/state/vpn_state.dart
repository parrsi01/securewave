import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/design/app_colors.dart';
import '../logging/app_logger.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_profile.dart';
import '../models/vpn_status.dart';
import '../optimization/marlxgb.dart';
import '../services/device_identity.dart';
import '../services/protocol_selector.dart';
import '../services/secure_storage.dart';
import 'vpn_state_machine.dart';
import '../../services/api_client.dart';
import '../services/auth_session.dart';
import '../services/vpn_service.dart';
import 'app_state.dart';
import 'preferences_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.protocol = VpnProtocol.auto,
    this.desiredOn = false,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.sessionTransferredBytes = 0,
    this.stabilityScore = 1.0,
    this.errorMessage,
    this.errorKind,
    this.effectiveProtocol,
    this.protocolMessage,
    this.failoverActive = false,
    this.failoverReason,
    this.failoverRegionId,
    this.lastProfileFetchAt,
    this.lastProfileFetchOk,
    this.lastTunnelStartAt,
    this.lastTunnelStartOk,
  });

  final VpnStatus status;
  final String? selectedServerId;
  final VpnProtocol protocol;
  final bool desiredOn;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final int sessionTransferredBytes;
  final double stabilityScore;
  final String? errorMessage;
  final VpnErrorKind? errorKind;
  final VpnProtocol? effectiveProtocol;
  final String? protocolMessage;
  final bool failoverActive;
  final String? failoverReason;
  final String? failoverRegionId;
  final DateTime? lastProfileFetchAt;
  final bool? lastProfileFetchOk;
  final DateTime? lastTunnelStartAt;
  final bool? lastTunnelStartOk;

  VpnState copyWith({
    VpnStatus? status,
    String? selectedServerId,
    VpnProtocol? protocol,
    bool? desiredOn,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    int? sessionTransferredBytes,
    double? stabilityScore,
    String? errorMessage,
    VpnErrorKind? errorKind,
    VpnProtocol? effectiveProtocol,
    String? protocolMessage,
    bool? failoverActive,
    String? failoverReason,
    String? failoverRegionId,
    DateTime? lastProfileFetchAt,
    bool? lastProfileFetchOk,
    DateTime? lastTunnelStartAt,
    bool? lastTunnelStartOk,
    bool clearError = false,
    bool clearEffectiveProtocol = false,
    bool clearProtocolMessage = false,
    bool clearFailover = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      protocol: protocol ?? this.protocol,
      desiredOn: desiredOn ?? this.desiredOn,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      sessionTransferredBytes:
          sessionTransferredBytes ?? this.sessionTransferredBytes,
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
      lastProfileFetchAt: lastProfileFetchAt ?? this.lastProfileFetchAt,
      lastProfileFetchOk: lastProfileFetchOk ?? this.lastProfileFetchOk,
      lastTunnelStartAt: lastTunnelStartAt ?? this.lastTunnelStartAt,
      lastTunnelStartOk: lastTunnelStartOk ?? this.lastTunnelStartOk,
    );
  }
}

final vpnStateProvider =
    StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

final vpnStateMachineConfigProvider = Provider<VpnStateMachineConfig>((ref) {
  return const VpnStateMachineConfig();
});

class VpnStateNotifier extends StateNotifier<VpnState> {
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
        if (previous == next || !next) return;
        _safeFireAndForget(
          _attemptAutoConnect(reason: 'auth_session_available'),
          context: 'auto_connect_auth_change',
        );
      },
    );
    _safeFireAndForget(_loadProtocol(), context: 'load_protocol');
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

  Timer? _rateTimer;
  int? _lastTrafficRxBytes;
  int? _lastTrafficTxBytes;
  DateTime? _lastTrafficSampleAt;
  bool _trafficPollInFlight = false;
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;
  DateTime? _lastAutoReconnectAt;

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

  @visibleForTesting
  bool get debugHasRateTimer => _rateTimer?.isActive ?? false;

  @visibleForTesting
  bool get debugHasActiveOperation => _activeOperation != null;

  @visibleForTesting
  List<VpnTransitionRecord> get debugTransitionHistory =>
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
      _transitionTo(
        next,
        trigger: VpnTransitionTrigger.initSync,
        force: true,
      );
      if (next == VpnStatus.connected) {
        _startRateSimulation();
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
        state.status == VpnStatus.disconnecting ||
        state.status == VpnStatus.error;
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
    debugPrint(
      '[VPN_DIAG] disconnect() called — desiredOn=${state.desiredOn} '
      'status=${state.status.name}\n'
      '${StackTrace.current.toString().split('\n').take(6).join('\n')}',
    );
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
        trigger: VpnTransitionTrigger.connectOperationFailed,
      );
      state = state.copyWith(
        errorKind: VpnErrorKind.unknown,
        errorMessage:
            'VPN tunnel appears down; kill switch may be blocking traffic.',
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
    await _requestReconcile();
  }

  void pauseRateUpdates() {
    _stopRateSimulation();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected && _rateTimer == null) {
      _startRateSimulation();
    }
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
    if (previous && !value) {
      debugPrint(
        '[VPN_DIAG] desiredOn flipped TRUE→FALSE source=$source\n'
        '${StackTrace.current.toString().split('\n').take(6).join('\n')}',
      );
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

  Future<void> _reconcileStep() async {
    if (!mounted) return;
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
        case VpnStatus.error:
          await _runConnectFlow();
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
            force: true,
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
            force: true,
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

  Future<void> _runConnectFlow() async {
    final op = _beginOperation(_VpnOperationAction.connect);
    _setBusy(true);
    _transitionTo(
      VpnStatus.connecting,
      trigger: VpnTransitionTrigger.connectOperationStarted,
      operationId: op.id,
    );
    state = state.copyWith(
      clearError: true,
      dataRateDown: 0,
      dataRateUp: 0,
      sessionTransferredBytes: 0,
      lastTunnelStartAt: DateTime.now(),
      lastTunnelStartOk: null,
    );

    try {
      final serversSnapshot = _ref.read(serversProvider);
      if (_allRegionsDown(serversSnapshot)) {
        throw VpnServiceException(
          'no_servers_available',
          'No servers available.',
        );
      }

      final service = _ref.read(vpnServiceProvider);
      final selectedProtocol = state.protocol;
      var failoverAttempted = false;
      final capabilities = await service
          .getCapabilities()
          .timeout(const Duration(seconds: 3), onTimeout: () {
        return VpnCapabilities.none;
      });
      final plan = const ProtocolSelector().resolve(
        selected: selectedProtocol,
        capabilities: capabilities,
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
        '"connectable":${plan.isConnectable}'
        '${plan.warning != null ? ',"warning":"${plan.warning}"' : ''}'
        '${plan.error != null ? ',"error":"${plan.error}"' : ''}}',
      );
      if (!plan.isConnectable) {
        throw VpnServiceException(
          'protocol_unavailable',
          plan.error ??
              'No supported VPN runtime is available for this protocol.',
        );
      }
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

      late final Map<String, dynamic> profile;
      try {
        profile = await _resolveVpnProfile(
          op: op,
          protocol: plan.backendProtocol,
          effectiveProtocol: plan.effective,
        );
      } catch (error) {
        final selectedRegionPinned =
            (state.selectedServerId ?? '').trim().isNotEmpty;
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

      _throwIfCancelled(op);
      final nextStatus = await service
          .connect(protocol: plan.effective, profile: profile)
          .timeout(_config.connectTimeout, onTimeout: () {
        op.cancel('runtime_connect_timeout');
        throw TimeoutException(
          'Runtime connect exceeded ${_config.connectTimeout.inSeconds}s.',
        );
      });
      _throwIfCancelled(op);

      if (nextStatus == VpnStatus.connected && !state.desiredOn) {
        await _disconnectAfterStaleConnect(service);
        _transitionTo(
          VpnStatus.disconnected,
          trigger: VpnTransitionTrigger.connectOperationCancelled,
          operationId: op.id,
          force: true,
        );
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
        );
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
        );
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
        _stopRateSimulation();
      }
    } on _VpnOperationCancelled catch (e) {
      debugPrint('[VPN_DIAG] connect op CANCELLED: ${e.reason}');
      _transitionTo(
        VpnStatus.disconnected,
        trigger: VpnTransitionTrigger.connectOperationCancelled,
        operationId: op.id,
      );
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
        errorKind: VpnErrorKind.backendError,
        errorMessage:
            'Connection timed out while starting the VPN tunnel. Please retry.',
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
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
      debugPrint(
        '[VPN_DEBUG] connect failure kind=${classified.kind.name} '
        'message=${classified.message} raw=${error.runtimeType}: $error',
      );
      state = state.copyWith(
        errorMessage: classified.message,
        errorKind: classified.kind,
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
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
    _transitionTo(
      VpnStatus.disconnecting,
      trigger: VpnTransitionTrigger.disconnectOperationStarted,
      operationId: op.id,
      force: state.status == VpnStatus.connecting,
    );

    try {
      final service = _ref.read(vpnServiceProvider);
      final nextStatus = await service.disconnect().timeout(
        _config.disconnectTimeout,
        onTimeout: () {
          op.cancel('runtime_disconnect_timeout');
          throw TimeoutException(
            'Runtime disconnect exceeded '
            '${_config.disconnectTimeout.inSeconds}s.',
          );
        },
      );
      final normalizedStatus =
          nextStatus == VpnStatus.error || nextStatus == VpnStatus.disconnecting
              ? VpnStatus.disconnected
              : nextStatus;
      _transitionTo(
        normalizedStatus,
        trigger: VpnTransitionTrigger.disconnectOperationSucceeded,
        operationId: op.id,
        force: true,
      );
      _stopRateSimulation();
      state = state.copyWith(
        dataRateDown: 0,
        dataRateUp: 0,
        sessionTransferredBytes: 0,
        clearError: true,
      );
      _updateStability(success: true);
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
            'Disconnect timed out while stopping the VPN tunnel. Please retry.',
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
        if (staleCachedDevice) {
          AppLogger.warning(
            '[VPN_SM] {"event":"profile_retry_without_cached_device","device_id":$deviceId}',
          );
          await _storage.delete(SecureStorage.vpnDeviceIdKey);
          _throwIfCancelled(op);
          profile = await fetchProfile(requestedDeviceId: null);
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

  Future<void> _disconnectAfterStaleConnect(VpnService service) async {
    try {
      await service.disconnect().timeout(_config.disconnectTimeout);
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
        '[VPN_SM] {"event":"transition_blocked","from":"${current.name}","to":"${next.name}","trigger":"${trigger.name}"}',
      );
      return false;
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
    }
    if (next == VpnStatus.connected) {
      _startRateSimulation();
    }
    state = state.copyWith(status: next);
    // ignore: avoid_print — explicit deterministic state trace for diagnostics
    debugPrint(
        'STATE TRANSITION: ${current.name} -> ${next.name} [${trigger.name}] desiredOn=${state.desiredOn}');
    AppLogger.info(
      '[VPN_SM] {"event":"transition","from":"${current.name}","to":"${next.name}","trigger":"${trigger.name}","operation_id":${operationId ?? (_activeOperation?.id ?? 0)}}',
    );
    return true;
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
      );
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
      await disconnect();
      if (!mounted || _disposed) return;
      await connect();
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
      if (error.code == 'protocol_unavailable') {
        return (kind: VpnErrorKind.protocolUnavailable, message: error.message);
      }
      if (error.code == 'no_servers_available' || error.code == 'region_down') {
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
        'no_servers_available',
        'region_down',
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
  String statusText({bool includeEllipsis = false}) {
    return switch (status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => includeEllipsis ? 'Connecting...' : 'Connecting',
      VpnStatus.disconnecting =>
        includeEllipsis ? 'Disconnecting...' : 'Disconnecting',
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
    return switch (errorKind) {
      VpnErrorKind.backendUnreachable => 'Backend unreachable',
      VpnErrorKind.backendError => 'Backend error',
      VpnErrorKind.auth => 'Sign-in required',
      VpnErrorKind.profileNotFound => 'Profile not found',
      VpnErrorKind.protocolUnavailable => 'Protocol unavailable',
      VpnErrorKind.permissionRequired => 'Permission required',
      VpnErrorKind.nativeUnavailable => 'VPN not available',
      VpnErrorKind.unknown || null => 'Connection failed',
    };
  }
}
