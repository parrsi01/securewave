import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vpn_status.dart';
import '../services/secure_storage.dart';
import '../../services/api_client.dart';
import '../utils/api_error.dart';
import 'app_state.dart';

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.healthLabel = 'Waiting',
    this.errorMessage,
  });

  final VpnStatus status;
  final int rxBytes;
  final int txBytes;
  final String healthLabel;
  final String? errorMessage;

  VpnState copyWith({
    VpnStatus? status,
    int? rxBytes,
    int? txBytes,
    String? healthLabel,
    String? errorMessage,
    bool clearError = false,
  }) => VpnState(
    status: status ?? this.status,
    rxBytes: rxBytes ?? this.rxBytes,
    txBytes: txBytes ?? this.txBytes,
    healthLabel: healthLabel ?? this.healthLabel,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

final vpnStateProvider = StateNotifierProvider<VpnStateNotifier, VpnState>((ref) {
  return VpnStateNotifier(ref);
});

class VpnStateNotifier extends StateNotifier<VpnState> {
  VpnStateNotifier(this._ref) : super(const VpnState()) {
    unawaited(_restoreStatus());
  }

  final Ref _ref;
  Timer? _trafficTimer;
  bool _operationInFlight = false;

  Future<void> _restoreStatus() async {
    final service = _ref.read(vpnServiceProvider);
    final snapshot = await service.refreshRuntimeStatus();
    if (!mounted) return;
    if (snapshot.status == VpnStatus.connected) {
      state = state.copyWith(status: VpnStatus.connected, healthLabel: 'Connected');
      _startTrafficPolling();
    }
  }

  Future<void> connect() async {
    if (_operationInFlight || state.status == VpnStatus.connected) return;
    _operationInFlight = true;
    state = state.copyWith(status: VpnStatus.connecting, healthLabel: 'Checking tunnel', clearError: true);
    try {
      final profile = await _ref.read(apiClientProvider).fetchVpnProfile(
        deviceName: 'SecureWave Linux',
        deviceType: 'linux',
        deviceId: await SecureStorage().getInt(SecureStorage.vpnDeviceIdKey),
      );
      if (profile.deviceId > 0) await SecureStorage().saveInt(SecureStorage.vpnDeviceIdKey, profile.deviceId);
      final result = await _ref.read(vpnServiceProvider).connect(config: profile.wireguardConfig);
      if (result != VpnStatus.connected) throw StateError('WireGuard did not reach a connected state.');
      state = state.copyWith(status: VpnStatus.connected, healthLabel: 'Good', clearError: true);
      _startTrafficPolling();
    } catch (error) {
      state = state.copyWith(status: VpnStatus.error, healthLabel: 'Unavailable', errorMessage: ApiError.messageFrom(error, fallback: 'SecureWave could not connect.'));
    } finally {
      _operationInFlight = false;
    }
  }

  Future<void> disconnect() async {
    if (_operationInFlight || state.status == VpnStatus.disconnected) return;
    _operationInFlight = true;
    _stopTrafficPolling();
    state = state.copyWith(status: VpnStatus.disconnecting, healthLabel: 'Stopping tunnel', clearError: true);
    try {
      await _ref.read(vpnServiceProvider).disconnect();
      state = state.copyWith(status: VpnStatus.disconnected, healthLabel: 'Waiting');
    } catch (error) {
      state = state.copyWith(status: VpnStatus.error, healthLabel: 'Unavailable', errorMessage: ApiError.messageFrom(error, fallback: 'SecureWave could not disconnect cleanly.'));
    } finally {
      _operationInFlight = false;
    }
  }

  void _startTrafficPolling() {
    _trafficTimer?.cancel();
    unawaited(_pollTraffic());
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_pollTraffic()));
  }

  void _stopTrafficPolling() {
    _trafficTimer?.cancel();
    _trafficTimer = null;
  }

  Future<void> _pollTraffic() async {
    if (!mounted || state.status != VpnStatus.connected) return;
    try {
      final stats = await _ref.read(vpnServiceProvider).getTrafficStats();
      if (!mounted) return;
      state = state.copyWith(
        rxBytes: stats.rxBytes,
        txBytes: stats.txBytes,
        healthLabel: stats.countersAvailable ? 'Good' : 'Connected',
      );
    } catch (_) {
      // Usage/health observation is non-blocking; the tunnel remains active.
    }
  }

  @override
  void dispose() {
    _stopTrafficPolling();
    super.dispose();
  }
}
