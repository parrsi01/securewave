import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Visual state enum
// ─────────────────────────────────────────────────────────────────────────────

/// Presentation-layer connection state. Decoupled from the internal
/// [VpnStatus] so the UI can express intermediate states (reconnecting)
/// without polluting the state machine.
enum ConnectionVisualState {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting,
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// Transition record — lightweight history entry
// ─────────────────────────────────────────────────────────────────────────────

class VpnTransitionRecord {
  const VpnTransitionRecord({
    required this.from,
    required this.to,
    required this.timestamp,
  });

  final VpnStatus from;
  final VpnStatus to;
  final DateTime timestamp;
}

// ─────────────────────────────────────────────────────────────────────────────
// Visual state resolver
// ─────────────────────────────────────────────────────────────────────────────

/// Maps the current [VpnState] + optional transition [history] to a
/// [ConnectionVisualState] for the presentation layer.
///
/// Reconnecting is detected when the current status is `connecting` but the
/// most recent history entry shows a transition from `connected` or `error`
/// within the last 15 seconds — indicating an automatic reconnection rather
/// than a user-initiated connect.
ConnectionVisualState resolveConnectionVisualState(
  VpnState state, [
  List<VpnTransitionRecord> history = const [],
]) {
  switch (state.status) {
    case VpnStatus.connected:
      return ConnectionVisualState.connected;

    case VpnStatus.disconnecting:
      return ConnectionVisualState.disconnecting;

    case VpnStatus.error:
      return ConnectionVisualState.error;

    case VpnStatus.connecting:
      // Detect reconnecting: if history shows a recent connected→X or
      // error→connecting transition, treat it as a reconnection.
      if (history.isNotEmpty) {
        final last = history.last;
        final age = DateTime.now().difference(last.timestamp);
        final isRecent = age.inSeconds < 15;
        final wasOnline =
            last.from == VpnStatus.connected || last.from == VpnStatus.error;
        if (isRecent && wasOnline && last.to == VpnStatus.connecting) {
          return ConnectionVisualState.reconnecting;
        }
      }
      // Also detect reconnecting via failoverActive flag
      if (state.failoverActive) {
        return ConnectionVisualState.reconnecting;
      }
      return ConnectionVisualState.connecting;

    case VpnStatus.disconnected:
      return ConnectionVisualState.disconnected;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selected server provider
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the currently selected [ServerRegion] by matching the
/// VPN state's `selectedServerId` against the servers list.
///
/// Returns null when no server is selected or the server list hasn't loaded.
final selectedServerProvider = Provider<ServerRegion?>((ref) {
  final vpnState = ref.watch(vpnStateProvider);
  final serverId = vpnState.selectedServerId;
  if (serverId == null || serverId.isEmpty) return null;

  final serversAsync = ref.watch(serversProvider);
  return serversAsync.whenOrNull<ServerRegion?>(
    data: (servers) {
      for (final server in servers) {
        if (server.id == serverId) return server;
      }
      return null;
    },
  );
});
