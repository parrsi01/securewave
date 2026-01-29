import 'dart:math';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/vpn_status.dart';
import '../services/vpn_service.dart';
import '../services/secure_storage.dart';
import 'app_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.errorMessage,
  });

  final VpnStatus status;
  final String? selectedServerId;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final String? errorMessage;

  VpnState copyWith({
    VpnStatus? status,
    String? selectedServerId,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VpnState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final vpnStateProvider = StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref)
      : super(VpnState(status: _ref.read(vpnServiceProvider).getStatus()));

  final Ref _ref;
  final _rng = Random();
  Timer? _rateTimer;

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId);
    if (serverId != null) {
      SecureStorage().saveString(SecureStorage.selectedServerKey, serverId);
    }
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
      final nextStatus = await service.connect();
      _setStatus(nextStatus);
      if (nextStatus == VpnStatus.connected) {
        _startRateSimulation();
      } else {
        _stopRateSimulation();
      }
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      state = state.copyWith(errorMessage: 'Unable to connect right now.');
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
    } catch (error, stackTrace) {
      _setStatus(VpnStatus.error);
      state = state.copyWith(errorMessage: 'Unable to disconnect right now.');
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
      state = state.copyWith(dataRateDown: down, dataRateUp: up);
    });
  }

  void _stopRateSimulation() {
    _rateTimer?.cancel();
    _rateTimer = null;
  }

  @override
  void dispose() {
    _rateTimer?.cancel();
    super.dispose();
  }
}
