import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final visualState = resolveConnectionVisualState(vpnState);
    final selectedServer = ref.watch(selectedServerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        StatusIndicator(visualState: visualState),
        const SizedBox(height: 24),
        ConnectButton(
          visualState: visualState,
          onTap: () {
            final notifier = ref.read(vpnStateProvider.notifier);
            if (visualState == ConnectionVisualState.connected ||
                visualState == ConnectionVisualState.connecting) {
              notifier.disconnect();
            } else {
              notifier.connect();
            }
          },
        ),
        const SizedBox(height: 24),
        TrafficStatsCard(vpnState: vpnState),
        if (selectedServer != null) ...[
          const SizedBox(height: 16),
          ServerLocationCard(server: selectedServer),
        ],
      ],
    );
  }
}
