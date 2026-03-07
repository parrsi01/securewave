import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import '../components/traffic_stats_card.dart';
import '../components/status_indicator.dart';

/// Connection detail screen — shows live tunnel stats.
class ConnectionScreen extends ConsumerWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);
    final selectedServer = ref.watch(selectedServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status row
              Row(
                children: [
                  StatusIndicator(visualState: visualState),
                  const SizedBox(width: AppSpacing.space3),
                  Text(
                    _statusLabel(visualState),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space5),

              // Server info
              if (selectedServer != null)
                _InfoTile(
                  icon: Icons.public_rounded,
                  label: 'Server',
                  value: '${selectedServer.name} · ${selectedServer.country ?? ''}',
                ),
              if (vpnState.effectiveProtocol != null)
                _InfoTile(
                  icon: Icons.lock_rounded,
                  label: 'Protocol',
                  value: vpnState.effectiveProtocol!.name.toUpperCase(),
                ),
              if (vpnState.status == VpnStatus.connected)
                _InfoTile(
                  icon: Icons.timer_outlined,
                  label: 'Session data',
                  value: formatBytesCompact(vpnState.sessionTransferredBytes),
                ),
              const SizedBox(height: AppSpacing.space5),

              TrafficStatsCard(vpnState: vpnState),
              const SizedBox(height: AppSpacing.space4),

              // Error message
              if (vpnState.errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                  ),
                  child: Text(
                    vpnState.errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(ConnectionVisualState s) {
    return switch (s) {
      ConnectionVisualState.connected => 'Connected',
      ConnectionVisualState.connecting => 'Connecting…',
      ConnectionVisualState.reconnecting => 'Reconnecting…',
      ConnectionVisualState.disconnecting => 'Disconnecting…',
      ConnectionVisualState.error => 'Error',
      ConnectionVisualState.disconnected => 'Disconnected',
    };
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconS, color: AppColors.primary),
          const SizedBox(width: AppSpacing.space3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
