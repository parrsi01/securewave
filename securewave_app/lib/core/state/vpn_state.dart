import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/vpn_profile.dart';
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
    bool clearSelectedServer = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      selectedServerId: clearSelectedServer
          ? null
          : (selectedServerId ?? this.selectedServerId),
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
    _protocolLoadFuture = _loadProtocol();
  }

  final Ref _ref;
  final _predictor = const MarLXGBPredictor();
  late final Future<void> _protocolLoadFuture;
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;
  DateTime? _lastAutoReconnectAt;

  Future<void> _loadProtocol() async {
    final storage = SecureStorage();
    final stored = await storage.getString(SecureStorage.vpnProtocolKey);
    final restored = vpnProtocolFromStorage(stored);
    if (restored != VpnProtocol.wireGuard) {
      // The current desktop UI intentionally exposes a WireGuard-only Beta
      // path. Discard protocol choices left by older multi-protocol builds so
      // an unavailable hidden choice cannot disable Connect permanently.
      await storage.delete(SecureStorage.vpnProtocolKey);
    }
    state = state.copyWith(protocol: VpnProtocol.wireGuard);
  }

  Future<void> resetConnectionSelection() async {
    await _protocolLoadFuture;
    if (_selectionLocked) return;
    state = state.copyWith(
      protocol: VpnProtocol.wireGuard,
      clearSelectedServer: true,
    );
    final storage = SecureStorage();
    await storage.delete(SecureStorage.selectedServerKey);
    await storage.delete(SecureStorage.vpnProtocolKey);
  }

  void selectServer(String? serverId) {
    if (_selectionLocked) return;
    _setSelectedServer(serverId);
  }

  void _setSelectedServer(String? serverId) {
    state = state.copyWith(
      selectedServerId: serverId,
      clearSelectedServer: serverId == null,
    );
    final storage = SecureStorage();
    if (serverId != null) {
      storage.saveString(SecureStorage.selectedServerKey, serverId);
    } else {
      storage.delete(SecureStorage.selectedServerKey);
    }
  }

  Future<void> selectProtocol(VpnProtocol protocol) async {
    await _protocolLoadFuture;
    if (_selectionLocked) return;
    state = state.copyWith(protocol: protocol);
    await SecureStorage().saveString(
      SecureStorage.vpnProtocolKey,
      vpnProtocolStorageValue(protocol),
    );
  }

  Future<void> connect() async {
    await _protocolLoadFuture;
    if (state.isBusy) return;

    final protocol = state.protocol;
    final requestedServerId = state.selectedServerId;
    final protocolKey = vpnProtocolStorageValue(protocol);

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
      String? connectedServerId = requestedServerId;

      if (service.isNativeAvailable) {
        final identity = await DeviceIdentity.load();
        final storage = SecureStorage();
        final deviceId = await storage.getInt(SecureStorage.vpnDeviceIdKey);
        final profileConfigKey = SecureStorage.vpnProfileConfigKeyFor(
          protocolKey,
        );
        try {
          final profile = await _fetchProfileWithReferenceRecovery(
            api: api,
            storage: storage,
            deviceId: deviceId,
            deviceName: identity.name,
            deviceType: identity.type,
            profileConfigKey: profileConfigKey,
            protocol: protocol,
            serverId: requestedServerId,
          );
          if (profile.protocol.trim().toLowerCase() != protocolKey) {
            throw VpnServiceException(
              'protocol_unavailable',
              'Backend returned a ${profile.protocol} profile for a $protocolKey request.',
            );
          }
          config = profile.configForProtocol(protocol);
          if (config.trim().isEmpty) {
            throw VpnServiceException(
              'protocol_unavailable',
              '${vpnProtocolLabel(protocol)} profile did not include a runnable Linux configuration.',
            );
          }
          if (profile.serverId.trim().isNotEmpty) {
            connectedServerId = profile.serverId;
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
          } else {
            await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
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
          if (_isProfileReferenceNotFound(error)) {
            await storage.delete(SecureStorage.vpnDeviceIdKey);
            await storage.delete(profileConfigKey);
            rethrow;
          }
          // Fallback: try last known config from secure storage for resilience.
          final cached = await storage.getString(profileConfigKey);
          final cachedExpiryRaw = await storage.getString(
            SecureStorage.vpnProfileExpiresAtKey,
          );
          final cachedExpiry = cachedExpiryRaw == null
              ? null
              : DateTime.tryParse(cachedExpiryRaw);
          if (!_canUseCachedProfileAfterFailure(error) ||
              cachedExpiry == null ||
              !cachedExpiry.isAfter(DateTime.now())) {
            await storage.delete(profileConfigKey);
            await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
            rethrow;
          }
          if (cached != null && cached.trim().isNotEmpty) {
            AppLogger.warning(
                'Using cached ${vpnProtocolLabel(protocol)} profile after a transport failure.');
            config = cached;
          } else {
            rethrow;
          }
        }
      }
      final nextStatus =
          await service.connect(protocol: protocol, config: config);
      _setStatus(nextStatus);
      if (nextStatus == VpnStatus.connected) {
        try {
          await api.notifyVpnConnected(
            serverId: connectedServerId,
            protocol: protocol,
          );
        } catch (_) {
          AppLogger.info('Backend connect notification skipped.');
        }
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: true,
        );
        _updateStability(success: true);
        _startRateUpdates();
      } else {
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: false,
        );
        _stopRateUpdates();
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
      _stopRateUpdates();
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

      _stopRateUpdates();
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

  Future<VpnProfile> _fetchProfileWithReferenceRecovery({
    required ApiClient api,
    required SecureStorage storage,
    required int? deviceId,
    required String deviceName,
    required String deviceType,
    required String profileConfigKey,
    required VpnProtocol protocol,
    required String? serverId,
  }) async {
    try {
      final profile = await api.fetchVpnProfile(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceType: deviceType,
        protocol: protocol,
        serverId: serverId,
      );
      state = state.copyWith(
        lastProfileFetchAt: DateTime.now(),
        lastProfileFetchOk: true,
      );
      return profile;
    } catch (error) {
      if (!_isProfileReferenceNotFound(error)) rethrow;

      final staleDevice = deviceId != null;
      final staleServer = serverId != null;
      if (!staleDevice && !staleServer) rethrow;

      if (staleDevice) {
        await storage.delete(SecureStorage.vpnDeviceIdKey);
        await storage.delete(profileConfigKey);
        AppLogger.warning(
          'Stored VPN device was not accepted by the backend; requesting a fresh profile.',
        );
      }
      if (staleServer) {
        _setSelectedServer(null);
        AppLogger.warning(
          'Stored VPN server was not accepted by the backend; retrying with auto-select.',
        );
      }

      final profile = await api.fetchVpnProfile(
        deviceName: deviceName,
        deviceType: deviceType,
        protocol: protocol,
        serverId: staleServer ? null : serverId,
      );
      state = state.copyWith(
        lastProfileFetchAt: DateTime.now(),
        lastProfileFetchOk: true,
      );
      return profile;
    }
  }

  bool _isProfileReferenceNotFound(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode != 404) return false;
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('404') && message.contains('not found');
  }

  bool _canUseCachedProfileAfterFailure(Object error) {
    if (error is! DioException || error.response != null) return false;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.unknown =>
        true,
      _ => false,
    };
  }

  bool get _selectionLocked {
    return state.isBusy ||
        state.status == VpnStatus.connected ||
        state.status == VpnStatus.connecting ||
        state.status == VpnStatus.disconnecting;
  }

  void _setStatus(VpnStatus status) {
    if (state.status != status) {
      AppLogger.info('VPN state -> ${status.name}');
    }
    state = state.copyWith(status: status);
  }

  void _startRateUpdates() {
    // The Linux bridge does not currently expose verified byte counters to
    // Dart. Keep rates at zero instead of showing synthetic traffic.
    state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
  }

  void _stopRateUpdates() {
    state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
  }

  void pauseRateUpdates() {
    _stopRateUpdates();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected) {
      _startRateUpdates();
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
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final apiCode = _apiErrorCode(error);
      final apiMessage = _apiErrorMessage(error);
      if (apiCode == 'device_limit_reached' ||
          apiMessage.toLowerCase().contains('device limit reached')) {
        return (
          kind: VpnErrorKind.deviceLimit,
          message: apiMessage.isNotEmpty
              ? apiMessage
              : 'Device limit reached. Revoke an old device or upgrade your plan.',
        );
      }
      if (statusCode == 401 || apiCode == 'unauthorized') {
        return (
          kind: VpnErrorKind.auth,
          message: 'Authentication failed. Please sign in again.',
        );
      }
      if (statusCode == 403) {
        return (
          kind: VpnErrorKind.backendError,
          message: apiMessage.isNotEmpty
              ? apiMessage
              : 'The VPN profile request was rejected by the backend.',
        );
      }
      if (statusCode == 404) {
        return (
          kind: VpnErrorKind.profileNotFound,
          message: apiMessage.isNotEmpty
              ? 'Profile fetch failed. $apiMessage'
              : 'Profile fetch failed. The backend could not resolve the selected VPN device or server.',
        );
      }
      if (statusCode == 500 || statusCode == 502 || statusCode == 503) {
        return (
          kind: VpnErrorKind.backendError,
          message: apiMessage.isNotEmpty
              ? apiMessage
              : 'Backend server error. The VPN service is experiencing issues. Please try again in a few minutes.',
        );
      }
    }
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

  String _apiErrorCode(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final nested = data['error'];
      if (nested is Map && nested['code'] != null) {
        return nested['code'].toString();
      }
      if (data['code'] != null) return data['code'].toString();
    }
    return '';
  }

  String _apiErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final nested = data['error'];
      if (nested is Map && nested['message'] != null) {
        return nested['message'].toString();
      }
      if (data['detail'] != null) return data['detail'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return error.message ?? '';
  }
}

enum VpnErrorKind {
  backendUnreachable,
  auth,
  deviceLimit,
  profileNotFound,
  backendError,
  protocolUnavailable,
  nativeUnavailable,
  unknown,
}
