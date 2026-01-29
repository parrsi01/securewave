import 'dart:math';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../optimization/marlxgb.dart';
import '../services/secure_storage.dart';
import 'app_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.protocol = VpnProtocol.wireGuard,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.stabilityScore = 1.0,
    this.errorMessage,
  });

  final VpnStatus status;
  final String? selectedServerId;
  final VpnProtocol protocol;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final double stabilityScore;
  final String? errorMessage;

  VpnState copyWith({
    VpnStatus? status,
    String? selectedServerId,
    VpnProtocol? protocol,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    double? stabilityScore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      protocol: protocol ?? this.protocol,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      stabilityScore: stabilityScore ?? this.stabilityScore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final vpnStateProvider = StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref)
      : super(VpnState(status: _ref.read(vpnServiceProvider).getStatus())) {
    _loadProtocol();
  }

  final Ref _ref;
  final _rng = Random();
  final _predictor = MarLXGBPredictor();
  Timer? _rateTimer;
  double _lastDown = 0;
  double _lastUp = 0;
  int _stabilitySuccesses = 0;
  int _stabilityFailures = 0;

  Future<void> _loadProtocol() async {
    final stored = await SecureStorage().getString(SecureStorage.vpnProtocolKey);
    state = state.copyWith(protocol: vpnProtocolFromStorage(stored));
  }

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId);
    if (serverId != null) {
      SecureStorage().saveString(SecureStorage.selectedServerKey, serverId);
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
    if (state.selectedServerId == null) {
      state = state.copyWith(errorMessage: 'Select a server region before connecting.');
      return;
    }
    if (state.isBusy) return;

    state = state.copyWith(isBusy: true, clearError: true);
    _setStatus(VpnStatus.connecting);
    AppLogger.info('VPN connect requested');
    try {
      final service = _ref.read(vpnServiceProvider);
      final nextStatus = await service.connect(protocol: state.protocol);
      _setStatus(nextStatus);
      if (nextStatus == VpnStatus.connected) {
        _updateStability(success: true);
        _startRateSimulation();
      } else {
        _stopRateSimulation();
      }
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      state = state.copyWith(errorMessage: 'Unable to connect right now.');
      _updateStability(success: false);
      AppLogger.error('VPN connect failed', error: error, stackTrace: stackTrace);
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> disconnect() async {
    if (state.isBusy) return;

    state = state.copyWith(isBusy: true, clearError: true);
    AppLogger.info('VPN disconnect requested');
    try {
      final service = _ref.read(vpnServiceProvider);
      final nextStatus = await service.disconnect();
      _setStatus(nextStatus);
      _stopRateSimulation();
      state = state.copyWith(dataRateDown: 0, dataRateUp: 0);
      _updateStability(success: true);
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      state = state.copyWith(errorMessage: 'Unable to disconnect right now.');
      _updateStability(success: false);
      AppLogger.error('VPN disconnect failed', error: error, stackTrace: stackTrace);
    } finally {
      state = state.copyWith(isBusy: false);
    }
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

  @override
  void dispose() {
    _rateTimer?.cancel();
    super.dispose();
  }
}
