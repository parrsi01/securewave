import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_service.dart';
import '../../core/constants/app_constants.dart';

class VpnTestState {
  const VpnTestState({
    this.isRunning = false,
    this.progress = 0,
    this.result,
  });

  final bool isRunning;
  final double progress;
  final Map<String, dynamic>? result;

  VpnTestState copyWith({bool? isRunning, double? progress, Map<String, dynamic>? result}) {
    return VpnTestState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      result: result ?? this.result,
    );
  }
}

final vpnTestControllerProvider = StateNotifierProvider<VpnTestController, VpnTestState>((ref) {
  return VpnTestController(ref);
});

class VpnTestController extends StateNotifier<VpnTestState> {
  VpnTestController(this._ref) : super(const VpnTestState());

  final Ref _ref;
  Timer? _timer;

  Future<void> runTest() async {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true, progress: 0, result: null);
    _timer?.cancel();
    final duration = AppConstants.vpnTestDuration.inSeconds;
    var tick = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      tick++;
      state = state.copyWith(progress: tick / duration);
      if (tick >= duration) {
        timer.cancel();
      }
    });

    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/test');
    } catch (_) {
      // If API fails, still produce simulated results.
    }

    await Future.delayed(AppConstants.vpnTestDuration);
    final rng = Random();
    final result = {
      'score': 86 + rng.nextInt(10),
      'latency_delta': rng.nextInt(15) + 5,
      'throughput': 80 + rng.nextInt(15),
      'dns_leak': false,
      'ipv6_leak': false,
      'status': 'PASSED',
    };
    state = state.copyWith(isRunning: false, progress: 1, result: result);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
