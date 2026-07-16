import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/vpn_profile.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_runtime_policy.dart';
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
    this.sessionRxBytes = 0,
    this.sessionTxBytes = 0,
    this.sessionCountersAvailable = false,
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
  final int sessionRxBytes;
  final int sessionTxBytes;
  final bool sessionCountersAvailable;
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
    int? sessionRxBytes,
    int? sessionTxBytes,
    bool? sessionCountersAvailable,
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
      sessionRxBytes: sessionRxBytes ?? this.sessionRxBytes,
      sessionTxBytes: sessionTxBytes ?? this.sessionTxBytes,
      sessionCountersAvailable:
          sessionCountersAvailable ?? this.sessionCountersAvailable,
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

final vpnStateProvider = StateNotifierProvider<VpnStateNotifier, VpnState>((
  ref,
) {
  return VpnStateNotifier(ref);
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref)
      : super(VpnState(status: _ref.read(vpnServiceProvider).getStatus())) {
    _initialization = _initialize();
    unawaited(_initialization);
  }

  final Ref _ref;
  late final Future<void> _initialization;
  final _predictor = const MarLXGBPredictor();
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;
  DateTime? _lastAutoReconnectAt;
  Timer? _usageTimer;
  VpnTrafficStats? _lastTrafficStats;
  DateTime? _lastTrafficStatsAt;
  bool _trafficPollInFlight = false;
  int _usageGeneration = 0;
  int? _activeDeviceId;
  String? _activeServerId;
  int? _usageSessionId;
  int _usageSequence = 0;

  Future<void> ensureInitialized() => _initialization;

  @override
  void dispose() {
    _usageTimer?.cancel();
    _usageTimer = null;
    _usageGeneration += 1;
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadProtocol();
    final service = _ref.read(vpnServiceProvider);
    for (final protocol in VpnProtocol.values) {
      await service.refreshProtocolAvailability(protocol);
      if (!mounted) return;
    }
    // Capability changes live inside the service; emit a fresh immutable state
    // so protocol tiles rebuild from fail-closed defaults.
    state = state.copyWith();
    if (!mounted ||
        state.isBusy ||
        state.desiredOn ||
        state.status != VpnStatus.disconnected) {
      return;
    }
    try {
      final snapshot = await service.refreshRuntimeStatus();
      if (!mounted || snapshot.status != VpnStatus.connected) return;
      final activeProtocol = snapshot.protocol ?? state.protocol;
      if (VpnRuntimePolicy.mustDisconnectAfterProcessRestore(activeProtocol)) {
        // A credentialed tunnel may survive a UI process restart, but this UI
        // has no trustworthy pre-connect egress baseline after restart. Do
        // not resurrect a green state from interface/process/XFRM evidence;
        // tear it down and require a fresh credential plus HTTPS proof.
        try {
          await service.disconnect();
        } catch (_) {
          // The next explicit action will surface the native cleanup failure.
        }
        return;
      }
      state = state.copyWith(
        status: VpnStatus.connected,
        protocol: activeProtocol,
        desiredOn: true,
        lastTunnelStartAt: DateTime.now(),
        lastTunnelStartOk: true,
      );
      _startRateUpdates();
    } catch (error, stackTrace) {
      AppLogger.error(
        'VPN runtime restore failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadProtocol() async {
    final storage = SecureStorage();
    final stored = await storage.getString(SecureStorage.vpnProtocolKey);
    if (!mounted) return;
    state = state.copyWith(protocol: vpnProtocolFromStorage(stored));
  }

  void selectServer(String? serverId) {
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
    state = state.copyWith(protocol: protocol);
    await SecureStorage().saveString(
      SecureStorage.vpnProtocolKey,
      vpnProtocolStorageValue(protocol),
    );
  }

  Future<void> connect({
    bool allowUnadvertisedOpenVpnCertification = false,
  }) async {
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
      if (!VpnRuntimePolicy.isReleased(state.protocol)) {
        throw VpnServiceException(
          'protocol_unavailable',
          VpnRuntimePolicy.unavailableReason(state.protocol),
        );
      }
      String? config;
      String? openVpnUsername;
      String? openVpnPassword;
      String? credentialedEgressBaseline;
      String? externalEgressBaseline;
      String? credentialedServerId;
      int? credentialedDeviceId;
      final requiresCredentialedEgress =
          VpnRuntimePolicy.requiresFreshEgressProof(state.protocol);
      var backendEvidence = false;

      if (service.isNativeAvailable) {
        final identity = await DeviceIdentity.load();
        final backendProtocols = await api.fetchProtocolAvailability(
          deviceType: identity.type,
        );
        final readiness = backendProtocols[state.protocol];
        final certificationBootstrap = allowUnadvertisedOpenVpnCertification &&
            state.protocol == VpnProtocol.openVpn &&
            readiness?.reason ==
                'OpenVPN data-plane evidence has not been recorded.';
        if (readiness == null ||
            (!readiness.enabled && !certificationBootstrap)) {
          throw VpnServiceException(
            'protocol_unavailable',
            readiness?.reason ??
                '${vpnProtocolLabel(state.protocol)} has no usable backend runtime evidence.',
          );
        }
        backendEvidence = true;
        final nativeProtocolReady = await service.refreshProtocolAvailability(
          state.protocol,
          backendEvidence: true,
        );
        if (!nativeProtocolReady) {
          throw VpnServiceException(
            'protocol_unavailable',
            service.protocolUnavailableReason(state.protocol) ??
                '${vpnProtocolLabel(state.protocol)} is unavailable on this Linux runtime.',
          );
        }
        if (requiresCredentialedEgress) {
          // Capture the public source before any routes change. The backend
          // returns only an HMAC fingerprint, never an address. IKEv2 and
          // OpenVPN must both prove encrypted HTTPS egress before UI state is
          // allowed to become connected.
          credentialedEgressBaseline = await api.captureVpnEgressBaseline();
          if (state.protocol == VpnProtocol.openVpn) {
            externalEgressBaseline = await api.captureExternalExitIp();
          }
        }
        final storage = SecureStorage();
        final deviceId = await storage.getInt(SecureStorage.vpnDeviceIdKey);
        final protocolKey = vpnProtocolStorageValue(state.protocol);
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
          );
          config = profile.configForProtocol(state.protocol);
          if (config.trim().isEmpty) {
            throw VpnServiceException(
              'protocol_unavailable',
              '${vpnProtocolLabel(state.protocol)} profile did not include a runnable Linux configuration.',
            );
          }
          if (state.protocol == VpnProtocol.openVpn) {
            openVpnUsername = profile.openVpnUsername;
            openVpnPassword = profile.openVpnPassword;
            if (openVpnUsername == null ||
                openVpnUsername.trim().isEmpty ||
                openVpnPassword == null ||
                openVpnPassword.isEmpty) {
              throw VpnServiceException(
                'protocol_unavailable',
                'OpenVPN profile did not include a fresh device credential.',
              );
            }
          }
          if (profile.deviceId > 0) {
            _activeDeviceId = profile.deviceId;
            await storage.saveInt(
              SecureStorage.vpnDeviceIdKey,
              profile.deviceId,
            );
          }
          _activeServerId = profile.serverId;
          if (requiresCredentialedEgress) {
            credentialedServerId = profile.serverId;
            credentialedDeviceId = profile.deviceId;
          }
          if (requiresCredentialedEgress) {
            // Credentialed profiles contain short-lived authorization data and
            // are deliberately never persisted for reconnect after expiry,
            // rotation, revocation, or a process restart.
            await storage.delete(profileConfigKey);
          } else {
            await storage.saveString(profileConfigKey, config);
          }
          if (profile.expiresAt != null) {
            await storage.saveString(
              SecureStorage.vpnProfileExpiresAtKey,
              profile.expiresAt!.toIso8601String(),
            );
          }
          if (!profile.peerRegistered && profile.registrationStatus != null) {
            AppLogger.warning(
              'Peer registration: ${profile.registrationStatus}',
            );
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
          // Credentialed profiles must always come from a fresh, authenticated
          // backend response. A cached profile can never contain a usable
          // secret after process restart, expiry, rotation, or revocation.
          if (requiresCredentialedEgress) rethrow;
          // Fallback: try last known config from secure storage for resilience.
          final cached = await storage.getString(profileConfigKey);
          if (cached != null && cached.trim().isNotEmpty) {
            AppLogger.warning(
              'Using cached ${vpnProtocolLabel(state.protocol)} profile (profile fetch failed).',
            );
            config = cached;
          } else {
            rethrow;
          }
        }
      } else {
        // Demo/mock path: notify the backend so it tracks the session,
        // but do not block on failures since the mock tunnel is local-only.
        try {
          await api.notifyVpnConnected(
            serverId: state.selectedServerId,
            protocol: state.protocol,
          );
        } catch (_) {
          AppLogger.info('Backend connect notification skipped (demo mode).');
        }
      }
      final nextStatus = await service.connect(
        protocol: state.protocol,
        config: config,
        openVpnUsername: openVpnUsername,
        openVpnPassword: openVpnPassword,
        backendEvidence: backendEvidence,
      );
      _setStatus(nextStatus);
      if (nextStatus == VpnStatus.connected) {
        if (service.isNativeAvailable && requiresCredentialedEgress) {
          final baseline = credentialedEgressBaseline;
          final serverId = credentialedServerId;
          final deviceId = credentialedDeviceId;
          var egressVerified = false;
          try {
            egressVerified = baseline != null &&
                serverId != null &&
                deviceId != null &&
                await api.verifyVpnEgress(
                  serverId: serverId,
                  deviceId: deviceId,
                  protocol: state.protocol,
                  baselineFingerprint: baseline,
                  externalBaselineIp: externalEgressBaseline,
                  externalExitIp: null,
                );
          } catch (_) {
            egressVerified = false;
          }
          if (!egressVerified &&
              state.protocol == VpnProtocol.openVpn &&
              externalEgressBaseline != null) {
            try {
              final tunnelExitIp = await api.captureExternalExitIp();
              if (baseline != null && serverId != null && deviceId != null) {
                try {
                  egressVerified = await api.verifyVpnEgress(
                    serverId: serverId,
                    deviceId: deviceId,
                    protocol: state.protocol,
                    baselineFingerprint: baseline,
                    externalBaselineIp: externalEgressBaseline,
                    externalExitIp: tunnelExitIp,
                  );
                } catch (_) {
                  egressVerified = false;
                }
              }
            } catch (_) {
              egressVerified = false;
            }
          }
          if (!egressVerified) {
            try {
              await service.disconnect();
            } catch (_) {
              // The original failed-proof error remains the useful outcome.
            }
            throw VpnServiceException(
              'vpn_egress_unverified',
              '${vpnProtocolLabel(state.protocol)} tunnel did not prove authenticated HTTPS exit-IP movement.',
            );
          }
        }
        try {
          await api.notifyVpnConnected(
            serverId: state.selectedServerId,
            protocol: state.protocol,
          );
        } catch (_) {
          AppLogger.info('Backend connect notification skipped.');
        }
        state = state.copyWith(
          lastTunnelStartAt: DateTime.now(),
          lastTunnelStartOk: true,
        );
        _updateStability(success: true);
        await _startUsageSession(api);
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
      AppLogger.error(
        'VPN connect failed',
        error: error,
        stackTrace: stackTrace,
      );
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
      _stopRateUpdates();
      final nextStatus = await service.disconnect();
      _setStatus(nextStatus);
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
        errorMessage: classified.message,
        errorKind: classified.kind,
      );
      _updateStability(success: false);
      AppLogger.error(
        'VPN disconnect failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      await _finalizeUsageSession();
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
  }) async {
    Future<VpnProfile> requestProfile({int? requestedDeviceId}) async {
      try {
        return await api.fetchVpnProfile(
          deviceId: requestedDeviceId,
          deviceName: deviceName,
          deviceType: deviceType,
          protocol: state.protocol,
          serverId: state.selectedServerId,
        );
      } catch (error) {
        if (!_isDeviceLimitReached(error)) rethrow;

        // The backend can reject a name-mismatched reinstall before it has a
        // chance to identify the existing peer. Reuse the one owner-scoped
        // active device, when the account has exactly one, instead of asking
        // the user to upgrade or manually revoke a still-usable device.
        final reusableDeviceId = await api.findReusableDeviceId(
          deviceType: deviceType,
        );
        if (reusableDeviceId == null || reusableDeviceId == requestedDeviceId) {
          rethrow;
        }
        final profile = await api.fetchVpnProfile(
          deviceId: reusableDeviceId,
          deviceName: deviceName,
          deviceType: deviceType,
          protocol: state.protocol,
          serverId: state.selectedServerId,
        );
        await storage.saveInt(SecureStorage.vpnDeviceIdKey, reusableDeviceId);
        return profile;
      }
    }

    try {
      final profile = await requestProfile(requestedDeviceId: deviceId);
      state = state.copyWith(
        lastProfileFetchAt: DateTime.now(),
        lastProfileFetchOk: true,
      );
      return profile;
    } catch (error) {
      if (!_isProfileReferenceNotFound(error)) rethrow;

      final staleDevice = deviceId != null;
      final staleServer = state.selectedServerId != null;
      if (!staleDevice && !staleServer) rethrow;

      if (staleDevice) {
        await storage.delete(SecureStorage.vpnDeviceIdKey);
        await storage.delete(profileConfigKey);
        AppLogger.warning(
          'Stored VPN device was not accepted by the backend; requesting a fresh profile.',
        );
      }
      if (staleServer) {
        selectServer(null);
        AppLogger.warning(
          'Stored VPN server was not accepted by the backend; retrying with auto-select.',
        );
      }

      final profile = await requestProfile();
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

  bool _isDeviceLimitReached(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final nested = data['error'];
        final code = nested is Map
            ? nested['code']?.toString()
            : data['code']?.toString();
        final detail = data['detail']?.toString() ??
            (nested is Map
                ? nested['message']?.toString()
                : data['message']?.toString()) ??
            '';
        return code == 'device_limit_reached' ||
            detail.toLowerCase().contains('device limit reached');
      }
      return false;
    }
    return error.toString().toLowerCase().contains('device limit reached');
  }

  void _setStatus(VpnStatus status) {
    if (state.status != status) {
      AppLogger.info('VPN state -> ${status.name}');
    }
    state = state.copyWith(status: status);
  }

  void _startRateUpdates({bool resetSession = true}) {
    _usageTimer?.cancel();
    _usageGeneration += 1;
    final generation = _usageGeneration;
    _lastTrafficStats = null;
    _lastTrafficStatsAt = null;
    _trafficPollInFlight = false;
    state = state.copyWith(
      dataRateDown: 0,
      dataRateUp: 0,
      sessionRxBytes: resetSession ? 0 : state.sessionRxBytes,
      sessionTxBytes: resetSession ? 0 : state.sessionTxBytes,
      sessionCountersAvailable: false,
    );
    unawaited(_pollTrafficStats(generation));
    _usageTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollTrafficStats(generation)),
    );
  }

  void _stopRateUpdates() {
    _usageTimer?.cancel();
    _usageTimer = null;
    _usageGeneration += 1;
    _trafficPollInFlight = false;
    _lastTrafficStats = null;
    _lastTrafficStatsAt = null;
    state = state.copyWith(
      dataRateDown: 0,
      dataRateUp: 0,
      sessionCountersAvailable: false,
    );
  }

  Future<void> _pollTrafficStats(int generation) async {
    if (_trafficPollInFlight || generation != _usageGeneration) return;
    if (state.status != VpnStatus.connected) return;
    _trafficPollInFlight = true;
    try {
      final stats =
          await _ref.read(vpnServiceProvider).getTrafficStats(state.protocol);
      if (!mounted || generation != _usageGeneration) return;
      if (!stats.countersAvailable) {
        state = state.copyWith(
          dataRateDown: 0,
          dataRateUp: 0,
          sessionCountersAvailable: false,
        );
        _lastTrafficStats = null;
        _lastTrafficStatsAt = null;
        return;
      }
      final now = DateTime.now();
      final previous = _lastTrafficStats;
      final previousAt = _lastTrafficStatsAt;
      _lastTrafficStats = stats;
      _lastTrafficStatsAt = now;
      if (previous == null || previousAt == null) {
        state = state.copyWith(sessionCountersAvailable: true);
        return;
      }
      final elapsedSeconds = now.difference(previousAt).inMicroseconds /
          Duration.microsecondsPerSecond;
      final rxDelta = stats.rxBytes >= previous.rxBytes
          ? stats.rxBytes - previous.rxBytes
          : 0;
      final txDelta = stats.txBytes >= previous.txBytes
          ? stats.txBytes - previous.txBytes
          : 0;
      final nextRxBytes = state.sessionRxBytes + rxDelta;
      final nextTxBytes = state.sessionTxBytes + txDelta;
      state = state.copyWith(
        dataRateDown: elapsedSeconds > 0 ? rxDelta / elapsedSeconds : 0,
        dataRateUp: elapsedSeconds > 0 ? txDelta / elapsedSeconds : 0,
        sessionRxBytes: nextRxBytes,
        sessionTxBytes: nextTxBytes,
        sessionCountersAvailable: true,
      );
      unawaited(_reportUsage(nextTxBytes, nextRxBytes));
    } catch (error, stackTrace) {
      AppLogger.error(
        'VPN traffic counter poll failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted && generation == _usageGeneration) {
        state = state.copyWith(
          dataRateDown: 0,
          dataRateUp: 0,
          sessionCountersAvailable: false,
        );
      }
    } finally {
      if (generation == _usageGeneration) {
        _trafficPollInFlight = false;
      }
    }
  }

  Future<void> _startUsageSession(ApiClient api) async {
    final deviceId = _activeDeviceId;
    final serverId = _activeServerId;
    if (deviceId == null ||
        deviceId <= 0 ||
        serverId == null ||
        serverId.isEmpty) {
      return;
    }
    _usageSequence = 0;
    try {
      _usageSessionId = await api.startUsageSession(
        deviceId: deviceId,
        serverId: serverId,
        protocol: state.protocol,
        idempotencyKey:
            'client-start-$deviceId-${DateTime.now().microsecondsSinceEpoch}',
      );
    } catch (error, stackTrace) {
      _usageSessionId = null;
      AppLogger.warning(
          'VPN usage session could not be started; tunnel remains active.');
      AppLogger.error('VPN usage session start failed',
          error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _reportUsage(int bytesSent, int bytesReceived) async {
    final sessionId = _usageSessionId;
    if (sessionId == null) return;
    final sequence = ++_usageSequence;
    try {
      await _ref.read(apiClientProvider).reportUsage(
            sessionId: sessionId,
            sequence: sequence,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            idempotencyKey: 'client-increment-$sessionId-$sequence',
          );
    } catch (error, stackTrace) {
      AppLogger.warning(
          'VPN usage report failed; will retry on the next counter poll.');
      AppLogger.error('VPN usage report error',
          error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _finalizeUsageSession() async {
    final sessionId = _usageSessionId;
    _usageSessionId = null;
    _usageSequence = 0;
    _activeDeviceId = null;
    _activeServerId = null;
    if (sessionId == null) return;
    try {
      await _ref.read(apiClientProvider).finalizeUsageSession(
            sessionId: sessionId,
            idempotencyKey:
                'client-disconnect-$sessionId-${DateTime.now().microsecondsSinceEpoch}',
          );
    } catch (error, stackTrace) {
      AppLogger.warning('VPN usage session finalization failed.');
      AppLogger.error('VPN usage finalization error',
          error: error, stackTrace: stackTrace);
    }
  }

  void pauseRateUpdates() {
    _stopRateUpdates();
  }

  void resumeRateUpdates() {
    if (state.status == VpnStatus.connected) {
      _startRateUpdates(resetSession: false);
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
