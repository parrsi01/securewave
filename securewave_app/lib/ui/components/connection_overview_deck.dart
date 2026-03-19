import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import 'connect_button.dart';
import 'server_location_card.dart';
import 'status_indicator.dart';
import 'traffic_stats_card.dart';

/// Compound widget: status + connect button + traffic stats + server pill.
///
/// Used on the home screen as a single scrollable deck.
class ConnectionOverviewDeck extends ConsumerWidget {
  const ConnectionOverviewDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = ref.watch(connectionVisualStateProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final selectedServer = ref.watch(selectedServerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        StatusIndicator(visualState: visualState),
        const SizedBox(height: 24),
        ConnectButton(
          visualState: visualState,
          connectPhaseLabel: vpnState.connectPhaseLabel,
          onTap: () {
            final notifier = ref.read(vpnStateProvider.notifier);
            if (primaryAction == ConnectionPrimaryAction.disconnect) {
              AppLogger.vpn('UI', 'DISCONNECT_BUTTON_PRESSED');
              notifier.disconnect();
            } else if (primaryAction == ConnectionPrimaryAction.connect) {
              AppLogger.vpn(
                'UI',
                'CONNECT_BUTTON_PRESSED',
                fields: <String, Object?>{
                  'server_id': vpnState.selectedServerId ?? 'auto',
                },
              );
              notifier.connect();
            }
          },
        ),
        const SizedBox(height: 24),
        const TrafficStatsCard(),
        if (selectedServer != null) ...[
          const SizedBox(height: 16),
          ServerLocationCard(server: selectedServer),
        ],
      ],
    );
  }
}
