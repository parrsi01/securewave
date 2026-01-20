import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/api_service.dart';
import '../../core/services/vpn_service.dart';

class VpnUiState {
  const VpnUiState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.lastSessionId,
  });

  final VpnStatus status;
  final String? selectedServerId;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final String? lastSessionId;

  VpnUiState copyWith({
    VpnStatus? status,
    String? selectedServerId,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    String? lastSessionId,
  }) {
    return VpnUiState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      lastSessionId: lastSessionId ?? this.lastSessionId,
    );
  }
}

final vpnControllerProvider = StateNotifierProvider<VpnController, VpnUiState>((ref) {
  return VpnController(ref);
});

class VpnController extends StateNotifier<VpnUiState> {
  VpnController(this._ref) : super(const VpnUiState()) {
    _statusSub = _ref.read(vpnServiceProvider).statusStream.listen((status) {
      state = state.copyWith(status: status);
      if (status == VpnStatus.connected) {
        _startRateSimulation();
      } else {
        _stopRateSimulation();
      }
    });
  }

  final Ref _ref;
  StreamSubscription<VpnStatus>? _statusSub;
  Timer? _rateTimer;
  final _rng = Random();

  void selectServer(String? serverId) {
    state = state.copyWith(selectedServerId: serverId);
  }

  Future<void> connect() async {
    if (state.selectedServerId == null) return;
    state = state.copyWith(isBusy: true);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/connect', data: {
        'server_id': state.selectedServerId,
        'session_id': const Uuid().v4(),
      });
      await _ref.read(vpnServiceProvider).connect();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(isBusy: true);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/disconnect');
      await _ref.read(vpnServiceProvider).disconnect();
    } finally {
      state = state.copyWith(isBusy: false, dataRateDown: 0, dataRateUp: 0);
    }
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
    _statusSub?.cancel();
    _rateTimer?.cancel();
    super.dispose();
  }
}
