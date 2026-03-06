import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../core/state/vpn_state_machine.dart';

enum ConnectionVisualState {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting,
  error,
}

final selectedServerProvider = Provider<ServerRegion?>((ref) {
  final selectedId =
      ref.watch(vpnStateProvider.select((state) => state.selectedServerId));
  final servers = ref.watch(serversProvider).valueOrNull;
  if (selectedId == null || selectedId.trim().isEmpty || servers == null) {
    return null;
  }
  for (final server in servers) {
    if (server.id == selectedId) return server;
  }
  return null;
});

ConnectionVisualState resolveConnectionVisualState(
  VpnState state,
  List<VpnTransitionRecord> history,
) {
  switch (state.status) {
    case VpnStatus.connected:
      return ConnectionVisualState.connected;
    case VpnStatus.disconnecting:
      return ConnectionVisualState.disconnecting;
    case VpnStatus.error:
      return ConnectionVisualState.error;
    case VpnStatus.disconnected:
      return ConnectionVisualState.disconnected;
    case VpnStatus.connecting:
      final recentlyConnected = history.reversed.take(4).any(
            (record) =>
                record.from == VpnStatus.connected ||
                record.trigger == VpnTransitionTrigger.autoReconnectRequested,
          );
      return state.desiredOn && recentlyConnected
          ? ConnectionVisualState.reconnecting
          : ConnectionVisualState.connecting;
  }
}
