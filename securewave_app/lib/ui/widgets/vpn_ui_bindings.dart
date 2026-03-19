import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../core/state/vpn_state_machine.dart';

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

enum ConnectionPrimaryAction {
  connect,
  disconnect,
  none,
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
  if (state.reconnectPending &&
      state.desiredOn &&
      (state.status == VpnStatus.disconnected ||
          state.status == VpnStatus.error)) {
    return ConnectionVisualState.reconnecting;
  }
  switch (state.status) {
    case VpnStatus.connected:
    case VpnStatus.degraded:
      return ConnectionVisualState.connected;

    case VpnStatus.disconnecting:
      return ConnectionVisualState.disconnecting;

    case VpnStatus.error:
      return ConnectionVisualState.error;

    case VpnStatus.connecting:
    case VpnStatus.verifying:
    case VpnStatus.reconnecting:
      // Detect reconnecting: if history shows a recent connected->X or
      // error->connecting transition, treat it as a reconnection.
      if (history.isNotEmpty) {
        final last = history.last;
        final age = DateTime.now().difference(last.at);
        final isRecent = age.inSeconds < 15;
        final wasOnline =
            last.from == VpnStatus.connected || last.from == VpnStatus.error;
        if (isRecent &&
            wasOnline &&
            (last.to == VpnStatus.connecting ||
                last.to == VpnStatus.verifying)) {
          return ConnectionVisualState.reconnecting;
        }
      }
      // Also detect reconnecting via failoverActive flag
      if (state.failoverActive) {
        return ConnectionVisualState.reconnecting;
      }
      return state.status == VpnStatus.reconnecting
          ? ConnectionVisualState.reconnecting
          : ConnectionVisualState.connecting;

    case VpnStatus.disconnected:
      return ConnectionVisualState.disconnected;
  }
}

bool connectionVisualStateIsBusy(ConnectionVisualState state) {
  return state == ConnectionVisualState.connecting ||
      state == ConnectionVisualState.reconnecting ||
      state == ConnectionVisualState.disconnecting;
}

bool connectionVisualStateHasActiveTunnel(ConnectionVisualState state) {
  return state == ConnectionVisualState.connected ||
      state == ConnectionVisualState.disconnecting;
}

bool connectionVisualStateSupportsLiveSwitch(ConnectionVisualState state) {
  return state == ConnectionVisualState.connected ||
      state == ConnectionVisualState.connecting ||
      state == ConnectionVisualState.reconnecting ||
      state == ConnectionVisualState.disconnecting;
}

ConnectionPrimaryAction resolveConnectionPrimaryAction(
  ConnectionVisualState state,
) {
  switch (state) {
    case ConnectionVisualState.connected:
      return ConnectionPrimaryAction.disconnect;
    case ConnectionVisualState.connecting:
    case ConnectionVisualState.reconnecting:
    case ConnectionVisualState.disconnecting:
      return ConnectionPrimaryAction.none;
    case ConnectionVisualState.disconnected:
    case ConnectionVisualState.error:
      return ConnectionPrimaryAction.connect;
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
  final serverId = ref.watch(
    vpnStateProvider.select((state) => state.selectedServerId),
  );
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

final connectionVisualStateProvider = Provider<ConnectionVisualState>((ref) {
  final visualStateFields = ref.watch(
    vpnStateProvider.select(
      (state) => (
        status: state.status,
        desiredOn: state.desiredOn,
        reconnectPending: state.reconnectPending,
        failoverActive: state.failoverActive,
      ),
    ),
  );
  final history = ref.read(vpnStateProvider.notifier).recentTransitions;
  return resolveConnectionVisualState(
    VpnState(
      status: visualStateFields.status,
      desiredOn: visualStateFields.desiredOn,
      reconnectPending: visualStateFields.reconnectPending,
      failoverActive: visualStateFields.failoverActive,
    ),
    history,
  );
});

final connectionPrimaryActionProvider =
    Provider<ConnectionPrimaryAction>((ref) {
  final visualState = ref.watch(connectionVisualStateProvider);
  return resolveConnectionPrimaryAction(visualState);
});

final connectionBusyProvider = Provider<bool>((ref) {
  final visualState = ref.watch(connectionVisualStateProvider);
  return connectionVisualStateIsBusy(visualState);
});

final connectionHasActiveTunnelProvider = Provider<bool>((ref) {
  final visualState = ref.watch(connectionVisualStateProvider);
  return connectionVisualStateHasActiveTunnel(visualState);
});

final connectionSupportsLiveSwitchProvider = Provider<bool>((ref) {
  final visualState = ref.watch(connectionVisualStateProvider);
  return connectionVisualStateSupportsLiveSwitch(visualState);
});
