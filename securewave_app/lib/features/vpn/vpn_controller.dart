import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/api_service.dart';
import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/utils/api_error.dart';

class VpnUiState {
  const VpnUiState({
    this.status = VpnStatus.disconnected,
    this.selectedServerId,
    this.isBusy = false,
    this.dataRateDown = 0,
    this.dataRateUp = 0,
    this.lastSessionId,
    this.lastConfig,
    this.errorMessage,
  });

  final VpnStatus status;
  final String? selectedServerId;
  final bool isBusy;
  final double dataRateDown;
  final double dataRateUp;
  final String? lastSessionId;
  final String? lastConfig;
  final String? errorMessage;

  VpnUiState copyWith({
    VpnStatus? status,
    String? selectedServerId,
    bool? isBusy,
    double? dataRateDown,
    double? dataRateUp,
    String? lastSessionId,
    String? lastConfig,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VpnUiState(
      status: status ?? this.status,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      isBusy: isBusy ?? this.isBusy,
      dataRateDown: dataRateDown ?? this.dataRateDown,
      dataRateUp: dataRateUp ?? this.dataRateUp,
      lastSessionId: lastSessionId ?? this.lastSessionId,
      lastConfig: lastConfig ?? this.lastConfig,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
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
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final api = _ref.read(apiServiceProvider);
      final config = await _allocateConfig(api);
      if (config == null) {
        state = state.copyWith(
          isBusy: false,
          errorMessage: 'Unable to provision VPN access. Please try again.',
        );
        return;
      }
      final sessionId = const Uuid().v4();
      await _ref.read(vpnServiceProvider).connect(config: config);
      await api.post('/vpn/connect', data: {
        'region': state.selectedServerId,
        'session_id': sessionId,
      });
      state = state.copyWith(lastSessionId: sessionId, lastConfig: config);
    } on DioException catch (error) {
      state = state.copyWith(errorMessage: ApiError.messageFrom(error));
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/disconnect');
      await _ref.read(vpnServiceProvider).disconnect();
    } on DioException catch (error) {
      state = state.copyWith(errorMessage: ApiError.messageFrom(error));
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

  Future<String?> _allocateConfig(ApiService api) async {
    try {
      final deviceName = _safeDeviceName(_ref.read(deviceInfoProvider));
      final response = await api.post('/vpn/allocate', data: {
        'server_id': state.selectedServerId,
        'device_name': deviceName,
      });
      final data = response.data as Map<String, dynamic>;
      return data['config'] as String?;
    } on DioException catch (error) {
      state = state.copyWith(errorMessage: ApiError.messageFrom(error));
      return null;
    } catch (_) {
      return null;
    }
  }

  String _safeDeviceName(String raw) {
    final trimmed = raw.replaceAll('\n', ' ').trim();
    if (trimmed.length <= 60) return trimmed;
    return trimmed.substring(0, 60);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _rateTimer?.cancel();
    super.dispose();
  }
}
