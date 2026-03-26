import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/components/htb_background.dart';
import '../../ui/components/neon_button.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/theme/app_colors.dart' as htb;
import '../../ui/widgets/glass_panel.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import '../components/protocol_selector_card.dart';
import '../components/traffic_graph_card.dart';
import '../components/traffic_stats_card.dart';
import '../components/status_indicator.dart';

/// Connection detail / live stats screen.
class ConnectionScreen extends ConsumerWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = ref.watch(connectionVisualStateProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final isBusy = ref.watch(connectionBusyProvider);
    final selectedServer = ref.watch(selectedServerProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Connection'),
        centerTitle: false,
      ),
      body: HtbScaffoldBackground(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              children: [
                _ConnectionOverview(
                  visualState: visualState,
                  serverLabel: selectedServer == null
                      ? 'Auto-selecting fastest server'
                      : '${selectedServer.name}${selectedServer.country != null ? ' · ${selectedServer.country}' : ''}',
                  protocolLabel:
                      (vpnState.effectiveProtocol ?? vpnState.protocol)
                          .name
                          .toUpperCase(),
                  latencyMs: selectedServer?.latencyMs,
                ),
                const SizedBox(height: AppSpacing.space4),
                GlassPanel(
                  child: Row(
                    children: [
                      StatusIndicator(visualState: visualState),
                      const Spacer(),
                      if (ref.watch(connectionHasActiveTunnelProvider))
                        _SessionTimer(connectedAt: vpnState.lastTunnelStartAt),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                _ConnectionActions(
                  primaryAction: primaryAction,
                  isBusy: isBusy,
                  onConnect: () {
                    AppLogger.vpn(
                      'UI',
                      'CONNECT_BUTTON_PRESSED',
                      fields: <String, Object?>{
                        'server_id': vpnState.selectedServerId ?? 'auto',
                        'screen': 'connection',
                      },
                    );
                    ref.read(vpnStateProvider.notifier).connect();
                  },
                  onDisconnect: () {
                    AppLogger.vpn(
                      'UI',
                      'DISCONNECT_BUTTON_PRESSED',
                      fields: const <String, Object?>{'screen': 'connection'},
                    );
                    ref.read(vpnStateProvider.notifier).disconnect();
                  },
                ),
                const SizedBox(height: AppSpacing.space4),
                const TrafficStatsCard(),
                const SizedBox(height: AppSpacing.space4),
                const TrafficGraphCard(),
                const SizedBox(height: AppSpacing.space4),
                const ProtocolSelectorCard(),
                const SizedBox(height: AppSpacing.space4),
                GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SESSION DETAILS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: htb.HtbColors.textMono,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      if (selectedServer != null)
                        InfoRow(
                          icon: Icons.public_rounded,
                          label: 'Server',
                          value:
                              '${selectedServer.name}${selectedServer.country != null ? ' \u00b7 ${selectedServer.country}' : ''}',
                        ),
                      if (vpnState.effectiveProtocol != null)
                        InfoRow(
                          icon: Icons.lock_rounded,
                          label: 'Protocol',
                          value: vpnState.effectiveProtocol!.name.toUpperCase(),
                        ),
                      if (selectedServer?.latencyMs != null)
                        InfoRow(
                          icon: Icons.speed_rounded,
                          label: 'Latency',
                          value: '${selectedServer!.latencyMs} ms',
                          valueColor: _latencyColor(selectedServer.latencyMs!),
                        ),
                      InfoRow(
                        icon: Icons.data_usage_rounded,
                        label: 'Session transferred',
                        value: formatBytesCompact(
                            vpnState.sessionTransferredBytes),
                      ),
                      InfoRow(
                        icon: Icons.timeline_rounded,
                        label: 'Stability',
                        value: '${(vpnState.stabilityScore * 100).round()}%',
                      ),
                    ],
                  ),
                ),
                if (vpnState.recoveryHeadline != null) ...[
                  const SizedBox(height: AppSpacing.space4),
                  _ConnectionRecoveryCard(vpnState: vpnState),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionOverview extends StatelessWidget {
  const _ConnectionOverview({
    required this.visualState,
    required this.serverLabel,
    required this.protocolLabel,
    required this.latencyMs,
  });

  final ConnectionVisualState visualState;
  final String serverLabel;
  final String protocolLabel;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = switch (visualState) {
      ConnectionVisualState.connected => 'Tunnel active',
      ConnectionVisualState.connecting => 'Negotiating tunnel',
      ConnectionVisualState.reconnecting => 'Recovering route',
      ConnectionVisualState.disconnecting => 'Closing session',
      ConnectionVisualState.error => 'Connection needs attention',
      ConnectionVisualState.disconnected => 'Tunnel offline',
    };

    return GlassPanel(
      glowColor: _accentForState(visualState),
      borderColor: _accentForState(visualState).withValues(alpha: 0.28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _accentForState(visualState).withValues(alpha: 0.12),
          htb.HtbColors.bg1.withValues(alpha: 0.9),
          htb.HtbColors.bg3.withValues(alpha: 0.96),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space3,
              vertical: AppSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: _accentForState(visualState).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: _accentForState(visualState).withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              'TUNNEL COMMAND',
              style: theme.textTheme.labelSmall?.copyWith(
                color: htb.HtbColors.textMono,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Connection control',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Live tunnel state, protocol selection, and session telemetry in one surface.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: htb.HtbColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              _OverviewChip(
                icon: Icons.radar_rounded,
                label: statusText,
                color: _accentForState(visualState),
              ),
              _OverviewChip(
                icon: Icons.public_rounded,
                label: serverLabel,
                color: AppColors.secondaryDark,
              ),
              _OverviewChip(
                icon: Icons.lock_rounded,
                label: protocolLabel,
                color: AppColors.primary,
              ),
              if (latencyMs != null)
                _OverviewChip(
                  icon: Icons.speed_rounded,
                  label: '$latencyMs ms',
                  color: _latencyColor(latencyMs!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _accentForState(ConnectionVisualState state) => switch (state) {
        ConnectionVisualState.connected => htb.HtbColors.accentPrimary,
        ConnectionVisualState.connecting => htb.HtbColors.accentSecondary,
        ConnectionVisualState.reconnecting => htb.HtbColors.statusConnecting,
        ConnectionVisualState.disconnecting => htb.HtbColors.textTertiary,
        ConnectionVisualState.error => htb.HtbColors.statusDisconnected,
        ConnectionVisualState.disconnected =>
          htb.HtbColors.accentSecondaryMuted,
      };
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.iconXS, color: color),
          const SizedBox(width: AppSpacing.space2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

Color _latencyColor(int ms) {
  if (ms < 50) return AppColors.success;
  if (ms < 100) return AppColors.warning;
  return AppColors.error;
}

class _ConnectionActions extends StatelessWidget {
  const _ConnectionActions({
    required this.primaryAction,
    required this.isBusy,
    required this.onConnect,
    required this.onDisconnect,
  });

  final ConnectionPrimaryAction primaryAction;
  final bool isBusy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final canConnect =
        primaryAction == ConnectionPrimaryAction.connect && !isBusy;
    final canDisconnect =
        primaryAction == ConnectionPrimaryAction.disconnect && !isBusy;

    return Row(
      children: [
        Expanded(
          child: NeonButton(
            label: 'Connect',
            icon: Icons.play_arrow_rounded,
            width: double.infinity,
            isConnecting:
                isBusy && primaryAction == ConnectionPrimaryAction.connect,
            onPressed: canConnect ? onConnect : null,
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Expanded(
          child: NeonOutlinedButton(
            label: 'Disconnect',
            icon: Icons.stop_rounded,
            width: double.infinity,
            accentColor: AppColors.error,
            onPressed: canDisconnect ? onDisconnect : null,
          ),
        ),
      ],
    );
  }
}

class _SessionTimer extends StatefulWidget {
  const _SessionTimer({required this.connectedAt});
  final DateTime? connectedAt;

  @override
  State<_SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<_SessionTimer> {
  late final Stream<Duration> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => widget.connectedAt == null
          ? Duration.zero
          : DateTime.now().difference(widget.connectedAt!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _stream,
      initialData: widget.connectedAt == null
          ? Duration.zero
          : DateTime.now().difference(widget.connectedAt!),
      builder: (_, snap) {
        final d = snap.data ?? Duration.zero;
        return Text(
          formatDurationClock(d),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: htb.HtbColors.accentPrimary,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

class _ConnectionRecoveryCard extends StatelessWidget {
  const _ConnectionRecoveryCard({required this.vpnState});

  final VpnState vpnState;

  @override
  Widget build(BuildContext context) {
    final title = vpnState.recoveryHeadline;
    final message = vpnState.recoveryMessage;
    if (title == null || message == null) {
      return const SizedBox.shrink();
    }

    final color = vpnState.killSwitchActive
        ? AppColors.error
        : (vpnState.reconnectPending || vpnState.failoverActive)
            ? AppColors.warning
            : AppColors.error;
    final icon = vpnState.killSwitchActive
        ? Icons.gpp_bad_rounded
        : vpnState.reconnectPending
            ? Icons.sync_rounded
            : vpnState.failoverActive
                ? Icons.swap_horiz_rounded
                : Icons.error_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppSpacing.iconS),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                ),
                if (vpnState.errorActionHint != null) ...[
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    vpnState.errorActionHint!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
