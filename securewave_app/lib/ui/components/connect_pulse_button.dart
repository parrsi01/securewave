/// Connection ring widget — the animated connect/disconnect button used on
/// the home screen. Alias for [ConnectButton] kept for backwards compatibility
/// with test imports.
library;

export 'connect_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import 'connect_button.dart';

/// Riverpod-wired version of [ConnectButton] for use in widget tests and
/// the home screen.
///
/// Reads [vpnStateProvider] and drives [VpnStateNotifier.connect] /
/// [VpnStateNotifier.disconnect] on tap. Blocks connect when all servers
/// are down or the selected region is offline.
class ConnectionRing extends ConsumerWidget {
  const ConnectionRing({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = ref.watch(connectionVisualStateProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final serversAsync = ref.watch(serversProvider);

    return ConnectButton(
      visualState: visualState,
      connectPhaseLabel: vpnState.connectPhaseLabel,
      onTap: () {
        final notifier = ref.read(vpnStateProvider.notifier);
        if (primaryAction == ConnectionPrimaryAction.disconnect) {
          AppLogger.vpn('UI', 'DISCONNECT_BUTTON_PRESSED');
          notifier.disconnect();
          return;
        }
        if (primaryAction == ConnectionPrimaryAction.none) {
          return;
        }

        // Guard: block connect if servers are unavailable
        final servers = serversAsync.valueOrNull ?? <ServerRegion>[];
        if (servers.isNotEmpty) {
          final allDown = servers.every((s) => s.regionHealthStatus == 'down');
          if (allDown) return;

          final selectedId = vpnState.selectedServerId;
          if (selectedId != null) {
            for (final s in servers) {
              if (s.id == selectedId && s.regionHealthStatus == 'down') {
                return;
              }
            }
          }
        }

        AppLogger.vpn('UI', 'CONNECT_BUTTON_PRESSED', fields: <String, Object?>{
          'server_id': vpnState.selectedServerId ?? 'auto',
        });
        notifier.connect();
      },
    );
  }
}
