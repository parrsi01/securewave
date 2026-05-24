import 'dart:math';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../optimization/marlxgb.dart';
import '../services/device_identity.dart';
import '../services/secure_storage.dart';
import '../../services/api_client.dart';
import '../services/vpn_service.dart';
import 'app_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.protocol = VpnProtocol.wireGuard,
    this.desiredOn = false,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.stabilityScore = 1.0,
    this.errorMessage,
    this.errorKind,
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
  final double stabilityScore;
  final String? errorMessage;
  final VpnErrorKind? errorKind;
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
    double? stabilityScore,
    String? errorMessage,
    VpnErrorKind? errorKind,
    DateTime? lastProfileFetchAt,
    bool? lastProfileFetchOk,
    DateTime? lastTunnelStartAt,
    bool? lastTunnelStartOk,
    bool clearError = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      protocol: protocol ?? this.protocol,
      desiredOn: desiredOn ?? this.desiredOn,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      stabilityScore: stabilityScore ?? this.stabilityScore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
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

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref)
      : super(VpnState(status: _ref.read(vpnServiceProvider).getStatus())) {
    _loadProtocol();
  }

  final Ref _ref;
  final _rng = Random();
  final _predictor = const MarLXGBPredictor();
  Timer? _rateTimer;
  double _lastDown = 0;
  double _lastUp = 0;
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;
  DateTime? _lastAutoReconnectAt;

  Future<void> _loadProtocol() async {
    final storage = SecureStorage();
    final stored = await storage.getString(SecureStorage.vpnProtocolKey);
    state = state.copyWith(protocol: vpnProtocolFromStorage(stored));
  }

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId);
    final storage = SecureStorage();
    if (serverId != null) {
      storage.saveString(SecureStorage.selectedServerKey, serverId);
    } else {
      storage.delete(SecureStorage.selectedServerKey);
    }
  }

  Future<void> selectProtocol(VpnProtocol protocol) async {
    state = state.copyWith(protocol: protocol);
    await SecureStorage().saveString(
      SecureStorage.vpnProtocolKey,
      vpnProtocolStorageValue(protocol),
    );
  }

  Future<void> connect() async {
    if (state.isBusy) return;

    // User intent: VPN should be on.
    final now = DateTime.now();
    state = state.copyWith(
      isBusy: true,
      desiredOn: true,
      clearError: true,
      lastTunnelStartAt: now,
      lastTunnelStartOk: null,
    );
    _setStatus(VpnStatus.connecting);
    AppLogger.info('VPN connect requested');
    try {
      final service = _ref.read(vpnServiceProvider);
      final api = _ref.read(apiClientProvider);
      String? config;

      if (service.isNativeAvailable) {
        final identity = await DeviceIdentity.load();
        final storage = SecureStorage();
        final deviceId = await storage.getInt(SecureStorage.vpnDeviceIdKey);
        final protocolKey = vpnProtocolStorageValue(state.protocol);
        final profileConfigKey = SecureStorage.vpnProfileConfigKeyFor(
          protocolKey,
        );
        try {
          final profile = await api.fetchVpnProfile(
            deviceId: deviceId,
            deviceName: identity.name,
            deviceType: identity.type,
            protocol: state.protocol,
            serverId: state.selectedServerId,
          );
          state = state.copyWith(
            lastProfileFetchAt: DateTime.now(),
            lastProfileFetchOk: true,
          );
          config = profile.configForProtocol(state.protocol);
          if (config.trim().isEmpty) {
            throw VpnServiceException(
              'protocol_unavailable',
              '${vpnProtocolLabel(state.protocol)} profile did not include a runnable Linux configuration.',
            );
          }
          if (profile.deviceId > 0) {
            await storage.saveInt(
                SecureStorage.vpnDeviceIdKey, profile.deviceId);
          }
          await storage.saveString(profileConfigKey, config);
          if (profile.expiresAt != null) {
            await storage.saveString(
              SecureStorage.vpnProfileExpiresAtKey,
              profile.expiresAt!.toIso8601String(),
            );
          }
          if (!profile.peerRegistered && profile.registrationStatus != null) {
            AppLogger.warning(
                'Peer registration: ${profile.registrationStatus}');
          }
        } catch (error) {
          state = state.copyWith(
            lastProfileFetchAt: DateTime.now(),
            lastProfileFetchOk: false,
          );
          // Fallback: try last known config from secure storage for resilience.
          final cached = await storage.getString(profileConfigKey);
          if (cached != null && cached.trim().isNotEmpty) {
            AppLogger.warning(
                'Using cached ${vpnProtocolLabel(state.protocol)} profile (profile fetch failed).');
            config = cached;
          } else {
            rethrow;
          }
        }
      } else {
        // Demo/mock path: notify the backend so it tracks the session,
        // but do not block on failures since the mock tunnel is local-only.
        try {
          await api.notifyVpnConnected(region: state.selectedServerId);
        } catch (_) {
          AppLogger.info('Backend connect notification skipped (demo mode).');
        }
      }
      final nextStatus =
          await service.connect(protocol: state.protocol, config: config);
      _setStatus(nextStatus);
      if (nextStatus == VpnStatus.connected) {
        try {
          await api.notifyVpnConnected(region: state.selectedServerId);
        } catch (_) {
          AppLogger.info('Backend connect notification skipped.');
        }
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: true,
        );
        _updateStability(success: true);
        _startRateSimulation();
      } else {
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
        );
        _stopRateSimulation();
      }
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      final classified = _classifyVpnError(error);
      state = state.copyWith(
        errorMessage: classified.message,
        errorKind: classified.kind,
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: false,
      );
      _updateStability(success: false);
      AppLogger.error('VPN connect failed',
          error: error, stackTrace: stackTrace);
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> disconnect() async {
    if (state.isBusy) return;

    // User intent: VPN should be off.
    state = state.copyWith(isBusy: true, desiredOn: false, clearError: true);
    AppLogger.info('VPN disconnect requested');
    _setStatus(VpnStatus.disconnecting);
    try {
      final service = _ref.read(vpnServiceProvider);
      final nextStatus = await service.disconnect();
      _setStatus(nextStatus);
      _stopRateSimulation();
      state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
      _updateStability(success: true);
      // Notify the backend so demo/live session tracking stays in sync.
      try {
        final api = _ref.read(apiClientProvider);
        await api.notifyVpnDisconnected();
      } catch (_) {
        AppLogger.info('Backend disconnect notification skipped.');
      }
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      final classified = _classifyVpnError(error);
      state = state.copyWith(
          errorMessage: classified.message, errorKind: classified.kind);
      _updateStability(success: false);
      AppLogger.error('VPN disconnect failed',
          error: error, stackTrace: stackTrace);
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> handleConnectivityChange({required bool hasNetwork}) async {
    if (!hasNetwork) {
      if (!state.desiredOn) return;
      if (state.isBusy) return;
      if (state.status != VpnStatus.connected) return;

      // Best-effort: if the Linux kill switch hooks are present and the
      // tunnel drops, traffic may be blocked, so "connected" becomes misleading.
      try {
        final storage = SecureStorage();
        final config = await storage.getString(
          SecureStorage.vpnProfileConfigKeyFor('wireguard'),
        );
        final hasKillSwitchHooks = (config ?? '').contains('PostUp') ||
            (config ?? '').contains('PostDown');
        if (!hasKillSwitchHooks) return;
      } catch (_) {
        return;
      }

      _stopRateSimulation();
      _setStatus(VpnStatus.error);
      state = state.copyWith(
        errorKind: VpnErrorKind.unknown,
        errorMessage:
            'VPN tunnel appears down; kill switch may be blocking traffic.',
        lastTunnelStartOk: false,
      );
      return;
    }
    if (!state.desiredOn) return;
    if (state.isBusy) return;
    if (state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting) {
      return;
    }

    final now = DateTime.now();
    if (_lastAutoReconnectAt != null &&
        now.difference(_lastAutoReconnectAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastAutoReconnectAt = now;

    AppLogger.info('Connectivity restored; attempting VPN reconnect.');
    // Fire-and-forget: state.isBusy gate prevents overlap.
    unawaited(connect());
  }

  void _setStatus(VpnStatus status) {
    if (state.status != status) {
      AppLogger.info('VPN state -> ${status.name}');
    }
    state = state.copyWith(status: status);
  }

  void _startRateSimulation() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final down = 25 + _rng.nextInt(120) + _rng.nextDouble();
      final up = 10 + _rng.nextInt(60) + _rng.nextDouble();
      _lastDown = _predictor.predictBandwidth(
        previous: _lastDown,
        sample: down,
        min: 5,
        max: 250,
      );
      _lastUp = _predictor.predictBandwidth(
        previous: _lastUp,
        sample: up,
        min: 2,
        max: 120,
      );
      state = state.copyWith(dataRateDown: _lastDown, dataRateUp: _lastUp);
    });
  }

  void _stopRateSimulation() {
    _rateTimer?.cancel();
    _rateTimer = null;
    _lastDown = 0;
    _lastUp = 0;
  }

  void pauseRateUpdates() {
    _stopRateSimulation();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected && _rateTimer == null) {
      _startRateSimulation();
    }
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

  ({VpnErrorKind kind, String message}) _classifyVpnError(Object error) {
    if (error is VpnServiceException) {
      if (error.code == 'protocol_unavailable') {
        return (kind: VpnErrorKind.protocolUnavailable, message: error.message);
      }
      if (error.code == 'vpn_unavailable' ||
          error.code == 'vpn_not_configured') {
        return (kind: VpnErrorKind.nativeUnavailable, message: error.message);
      }
      return (kind: VpnErrorKind.unknown, message: error.message);
    }
    if (error is StateError) {
      return (kind: VpnErrorKind.unknown, message: error.message);
    }
    // Check for network/backend-unreachable errors
    final msg = error.toString().toLowerCase();
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
    _rateTimer?.cancel();
    super.dispose();
  }
}

enum VpnErrorKind {
  backendUnreachable,
  auth,
  profileNotFound,
  backendError,
  protocolUnavailable,
  nativeUnavailable,
  unknown,
}
