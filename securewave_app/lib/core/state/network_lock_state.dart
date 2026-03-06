import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkLockState {
  const NetworkLockState({
    this.isLocked = false,
    this.reason,
    this.lockedAt,
  });

  final bool isLocked;
  final String? reason;
  final DateTime? lockedAt;

  NetworkLockState copyWith({
    bool? isLocked,
    String? reason,
    DateTime? lockedAt,
    bool clearReason = false,
  }) {
    return NetworkLockState(
      isLocked: isLocked ?? this.isLocked,
      reason: clearReason ? null : (reason ?? this.reason),
      lockedAt: lockedAt ?? this.lockedAt,
    );
  }
}

final networkLockProvider =
    StateNotifierProvider<NetworkLockController, NetworkLockState>((ref) {
  return NetworkLockController();
});

class NetworkLockController extends StateNotifier<NetworkLockState> {
  NetworkLockController() : super(const NetworkLockState());

  void engage(String reason) {
    state = NetworkLockState(
      isLocked: true,
      reason: reason,
      lockedAt: DateTime.now(),
    );
  }

  void release() {
    state = state.copyWith(
      isLocked: false,
      clearReason: true,
      lockedAt: DateTime.now(),
    );
  }
}
