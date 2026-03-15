import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/vpn_state.dart';
import '../components/connect_button.dart';
import '../components/protocol_selector_card.dart';
import '../components/status_display.dart';
import '../components/traffic_graph_card.dart';
import '../components/traffic_stats_card.dart';
import '../components/usage_meter_card.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Main dashboard.
class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = ref.watch(connectionVisualStateProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= AppSpacing.tabletBreakpoint;
    final maxWidth = isWide ? 1180.0 : 760.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = visualState == ConnectionVisualState.connected;

    void onConnectTap() {
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
    }

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: isDark
              ? (isConnected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF103128), Color(0xFF081424)],
                    )
                  : AppColors.navyGradient)
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF4F8FB), Color(0xFFFDFEFF)],
                ),
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.space4,
                  AppSpacing.pagePadding,
                  AppSpacing.space6,
                ),
                children: [
                  _DashboardHeader(
                    onAccountTap: () => context.go('/account'),
                    onSettingsTap: () => context.go('/settings'),
                  ),
                  const SizedBox(height: AppSpacing.space5),

                  // ── Connection Hero ─────────────────────────────────────
                  _ConnectionHero(
                    vpnState: vpnState,
                    visualState: visualState,
                    selectedServerLabel: selectedServer?.name,
                    latencyMs: selectedServer?.latencyMs,
                    onServerTap: () => context.go('/servers'),
                    onConnectTap: onConnectTap,
                  ),

                  const SizedBox(height: AppSpacing.space4),

                  // ── Stats + Side Panel ──────────────────────────────────
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            children: [
                              TrafficStatsCard(vpnState: vpnState),
                              const SizedBox(height: AppSpacing.space4),
                              const TrafficGraphCard(),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space4),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              const UsageMeterCard(),
                              const SizedBox(height: AppSpacing.space4),
                              const ProtocolSelectorCard(),
                              const SizedBox(height: AppSpacing.space4),
                              _QuickActionPanel(
                                vpnState: vpnState,
                                onServersTap: () => context.go('/servers'),
                                onConnectionTap: () =>
                                    context.go('/connection'),
                                onDiagnosticsTap: () =>
                                    context.go('/diagnostics'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        TrafficStatsCard(vpnState: vpnState),
                        const SizedBox(height: AppSpacing.space4),
                        const UsageMeterCard(),
                        const SizedBox(height: AppSpacing.space4),
                        const ProtocolSelectorCard(),
                        const SizedBox(height: AppSpacing.space4),
                        const TrafficGraphCard(),
                        const SizedBox(height: AppSpacing.space4),
                        _QuickActionPanel(
                          vpnState: vpnState,
                          onServersTap: () => context.go('/servers'),
                          onConnectionTap: () => context.go('/connection'),
                          onDiagnosticsTap: () => context.go('/diagnostics'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dashboard Header ──────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.onAccountTap,
    required this.onSettingsTap,
  });

  final VoidCallback onAccountTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'SecureWave',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        IconButton.filledTonal(
          onPressed: onSettingsTap,
          icon: const Icon(Icons.tune_rounded),
        ),
        const SizedBox(width: AppSpacing.space2),
        FilledButton.tonalIcon(
          onPressed: onAccountTap,
          icon: const Icon(Icons.person_outline_rounded),
          label: const Text('Account'),
        ),
      ],
    ).animate().fadeIn(duration: 260.ms).slideY(begin: -0.08, end: 0);
  }
}

// ── Connection Hero ───────────────────────────────────────────────────────────

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.vpnState,
    required this.visualState,
    required this.selectedServerLabel,
    required this.latencyMs,
    required this.onServerTap,
    required this.onConnectTap,
  });

  final VpnState vpnState;
  final ConnectionVisualState visualState;
  final String? selectedServerLabel;
  final int? latencyMs;
  final VoidCallback onServerTap;
  final VoidCallback onConnectTap;

  @override
  Widget build(BuildContext context) {
    final protocolLabel =
        vpnProtocolLabel(vpnState.effectiveProtocol ?? vpnState.protocol);

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space6,
      ),
      child: Column(
        children: [
          // ── Status indicator + banners ───────────────────────────────
          const StatusDisplay(),

          const SizedBox(height: AppSpacing.space5),

          // ── Hero connect button (dominant visual) ────────────────────
          ConnectButton(
            visualState: visualState,
            connectPhaseLabel: vpnState.connectPhaseLabel,
            onTap: onConnectTap,
          ),

          const SizedBox(height: AppSpacing.space5),

          // ── Status headline (animated crossfade) ─────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _headlineFor(visualState, vpnState.connectPhaseLabel),
              key: ValueKey('${visualState}_${vpnState.connectPhaseLabel}'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            _subtitleFor(visualState, vpnState),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),

          const SizedBox(height: AppSpacing.space5),

          // ── Server + Latency + Protocol chips ────────────────────────
          _InfoChipRow(
            serverLabel: selectedServerLabel,
            latencyMs: latencyMs,
            protocolLabel: protocolLabel,
            stabilityPct: (vpnState.stabilityScore * 100).round(),
            onServerTap: onServerTap,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }

  String _headlineFor(ConnectionVisualState state, String? phaseLabel) =>
      switch (state) {
        ConnectionVisualState.connected => 'Tunnel active',
        ConnectionVisualState.connecting =>
          phaseLabel ?? 'Starting secure tunnel',
        ConnectionVisualState.reconnecting => 'Rebuilding secure path',
        ConnectionVisualState.disconnecting => 'Stopping tunnel',
        ConnectionVisualState.error => 'Tunnel needs attention',
        ConnectionVisualState.disconnected => 'Ready to protect traffic',
      };

  String _subtitleFor(ConnectionVisualState state, VpnState vpnState) =>
      switch (state) {
        ConnectionVisualState.connected =>
          'Traffic is flowing through the current SecureWave route.',
        ConnectionVisualState.connecting =>
          'Authenticating, fetching profile, and bringing the tunnel online.',
        ConnectionVisualState.reconnecting => vpnState.recoveryMessage ??
            'Recovering the session after a network or region change.',
        ConnectionVisualState.disconnecting =>
          'Closing the active session and clearing route state.',
        ConnectionVisualState.error => vpnState.recoveryMessage ??
            'Diagnostics are available if the tunnel could not be established.',
        ConnectionVisualState.disconnected =>
          'Pick a region or protocol and connect when ready.',
      };
}

// ── Info Chip Row ─────────────────────────────────────────────────────────────

class _InfoChipRow extends StatelessWidget {
  const _InfoChipRow({
    required this.serverLabel,
    required this.latencyMs,
    required this.protocolLabel,
    required this.stabilityPct,
    required this.onServerTap,
  });

  final String? serverLabel;
  final int? latencyMs;
  final String protocolLabel;
  final int stabilityPct;
  final VoidCallback onServerTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      children: [
        _InfoChip(
          icon: Icons.dns_rounded,
          label: serverLabel ?? 'Auto-select',
          onTap: onServerTap,
        ),
        if (latencyMs != null && latencyMs! > 0)
          _InfoChip(
            icon: Icons.speed_rounded,
            label: latencyLabel(latencyMs),
            color: _latencyColor(latencyMs!),
          ),
        _InfoChip(
          icon: Icons.lock_rounded,
          label: protocolLabel,
        ),
        _InfoChip(
          icon: Icons.timeline_rounded,
          label: '$stabilityPct%',
        ),
      ],
    );
  }

  Color _latencyColor(int ms) {
    if (ms < 50) return AppColors.success;
    if (ms < 100) return AppColors.warning;
    return AppColors.error;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppSpacing.iconS,
            color: color ?? AppColors.primaryBright,
          ),
          const SizedBox(width: AppSpacing.space2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.space1),
            Icon(
              Icons.chevron_right_rounded,
              size: AppSpacing.iconXS,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }
}

// ── Quick Action Panel ────────────────────────────────────────────────────────

class _QuickActionPanel extends StatelessWidget {
  const _QuickActionPanel({
    required this.vpnState,
    required this.onServersTap,
    required this.onConnectionTap,
    required this.onDiagnosticsTap,
  });

  final VpnState vpnState;
  final VoidCallback onServersTap;
  final VoidCallback onConnectionTap;
  final VoidCallback onDiagnosticsTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Control Center',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.space4),
          _ActionButton(
            icon: Icons.public_rounded,
            title: 'Server Selection',
            subtitle: 'Switch regions and compare latency',
            onTap: onServersTap,
          ),
          const SizedBox(height: AppSpacing.space2),
          _ActionButton(
            icon: Icons.shield_rounded,
            title: 'Connection Detail',
            subtitle: 'Inspect tunnel metrics and session data',
            onTap: onConnectionTap,
          ),
          const SizedBox(height: AppSpacing.space2),
          _ActionButton(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostics',
            subtitle: 'Verify readiness, logs, and failover signals',
            onTap: onDiagnosticsTap,
          ),
          const SizedBox(height: AppSpacing.space4),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Icon(
                Icons.data_usage_rounded,
                size: AppSpacing.iconS,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.space2),
              Text(
                'Session: ${formatBytesCompact(vpnState.sessionTransferredBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          if (vpnState.errorMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              vpnState.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 360.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryBright.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                ),
                child: Icon(icon, color: AppColors.primaryBright),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
