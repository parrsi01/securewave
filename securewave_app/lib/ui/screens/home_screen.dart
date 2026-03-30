import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/vpn_state.dart';
import '../components/connect_button.dart';
import '../components/health_badge.dart';
import '../components/protocol_selector_card.dart';
import '../components/status_display.dart';
import '../components/usage_meter_card.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import '../widgets/brand_mark.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Main dashboard — native Material 3 layout, no glass/glow overlays.
class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeVpn = ref.watch(
      vpnStateProvider.select(
        (state) => (
          selectedServerId: state.selectedServerId,
          protocol: state.protocol,
          effectiveProtocol: state.effectiveProtocol,
          connectPhaseLabel: state.connectPhaseLabel,
          stabilityPct: (state.stabilityScore * 100).round(),
          recoveryMessage: state.recoveryMessage,
          sessionTransferredBytes: state.sessionTransferredBytes,
          errorMessage: state.errorMessage,
        ),
      ),
    );
    final visualState = ref.watch(connectionVisualStateProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final isWide = MediaQuery.sizeOf(context).width >= AppSpacing.tabletBreakpoint;
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
            'server_id': homeVpn.selectedServerId ?? 'auto',
          },
        );
        notifier.connect();
      }
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: isWide
            ? _WideLayout(
                visualState: visualState,
                homeVpn: homeVpn,
                selectedServer: selectedServer,
                isConnected: isConnected,
                onConnectTap: onConnectTap,
              )
            : _NarrowLayout(
                visualState: visualState,
                homeVpn: homeVpn,
                selectedServer: selectedServer,
                isConnected: isConnected,
                onConnectTap: onConnectTap,
                cs: cs,
              ),
      ),
    );
  }
}

// ── Narrow (mobile) layout ────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.visualState,
    required this.homeVpn,
    required this.selectedServer,
    required this.isConnected,
    required this.onConnectTap,
    required this.cs,
  });

  final ConnectionVisualState visualState;
  final ({
    String? selectedServerId,
    VpnProtocol protocol,
    VpnProtocol? effectiveProtocol,
    String? connectPhaseLabel,
    int stabilityPct,
    String? recoveryMessage,
    int sessionTransferredBytes,
    String? errorMessage,
  }) homeVpn;
  final dynamic selectedServer;
  final bool isConnected;
  final VoidCallback onConnectTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final protocolLabel =
        vpnProtocolLabel(homeVpn.effectiveProtocol ?? homeVpn.protocol);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ── Brand header ───────────────────────────────────────────────────
        Row(
          children: [
            const BrandMark(size: 28, textSize: 20),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => GoRouter.of(context).go('/settings'),
              tooltip: 'Settings',
            ),
            IconButton(
              icon: const Icon(Icons.person_outline_rounded),
              onPressed: () => GoRouter.of(context).go('/account'),
              tooltip: 'Account',
            ),
          ],
        ).animate().fadeIn(duration: 250.ms),

        const SizedBox(height: 16),

        // ── Status + connect button ────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                const StatusDisplay(),
                if (isConnected) ...[
                  const SizedBox(height: 12),
                  const HealthBadge(),
                ],
                const SizedBox(height: 24),
                ConnectButton(
                  visualState: visualState,
                  connectPhaseLabel: homeVpn.connectPhaseLabel,
                  onTap: onConnectTap,
                ),
                const SizedBox(height: 20),
                _StatusHeadline(
                  visualState: visualState,
                  connectPhaseLabel: homeVpn.connectPhaseLabel,
                  recoveryMessage: homeVpn.recoveryMessage,
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 300.ms),

        const SizedBox(height: 12),

        // ── Server + protocol info ─────────────────────────────────────────
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: const Text('Server'),
                subtitle:
                    Text(selectedServer?.name ?? 'Auto-select'),
                trailing: selectedServer?.latencyMs != null
                    ? _LatencyChip(ms: selectedServer!.latencyMs as int)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => GoRouter.of(context).go('/servers'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.lock_rounded),
                title: const Text('Protocol'),
                subtitle: Text(protocolLabel),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${homeVpn.stabilityPct}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => GoRouter.of(context).go('/connection'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        const UsageMeterCard(),
        const SizedBox(height: 12),
        const ProtocolSelectorCard(),

        const SizedBox(height: 12),

        // ── Quick actions ─────────────────────────────────────────────────
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('Server Selection'),
                subtitle: const Text('Switch regions and compare latency'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => GoRouter.of(context).go('/servers'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.shield_rounded),
                title: const Text('Connection Detail'),
                subtitle: const Text('Inspect tunnel metrics and session data'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => GoRouter.of(context).go('/connection'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Diagnostics'),
                subtitle:
                    const Text('Verify readiness, logs, and failover signals'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => GoRouter.of(context).go('/diagnostics'),
              ),
            ],
          ),
        ),

        if (homeVpn.errorMessage?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18,
                      color: htb.HtbColors.statusError),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      homeVpn.errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: htb.HtbColors.statusError,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Wide (tablet/desktop) layout ──────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.visualState,
    required this.homeVpn,
    required this.selectedServer,
    required this.isConnected,
    required this.onConnectTap,
  });

  final ConnectionVisualState visualState;
  final ({
    String? selectedServerId,
    VpnProtocol protocol,
    VpnProtocol? effectiveProtocol,
    String? connectPhaseLabel,
    int stabilityPct,
    String? recoveryMessage,
    int sessionTransferredBytes,
    String? errorMessage,
  }) homeVpn;
  final dynamic selectedServer;
  final bool isConnected;
  final VoidCallback onConnectTap;

  @override
  Widget build(BuildContext context) {
    final protocolLabel =
        vpnProtocolLabel(homeVpn.effectiveProtocol ?? homeVpn.protocol);
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column — connect + info
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 24),
            children: [
              Row(
                children: [
                  const BrandMark(size: 32, textSize: 22),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () => GoRouter.of(context).go('/settings'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_outline_rounded),
                    onPressed: () => GoRouter.of(context).go('/account'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Column(
                    children: [
                      const StatusDisplay(),
                      if (isConnected) ...[
                        const SizedBox(height: 12),
                        const HealthBadge(),
                      ],
                      const SizedBox(height: 28),
                      ConnectButton(
                        visualState: visualState,
                        connectPhaseLabel: homeVpn.connectPhaseLabel,
                        onTap: onConnectTap,
                      ),
                      const SizedBox(height: 20),
                      _StatusHeadline(
                        visualState: visualState,
                        connectPhaseLabel: homeVpn.connectPhaseLabel,
                        recoveryMessage: homeVpn.recoveryMessage,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.dns_rounded),
                      title: const Text('Server'),
                      subtitle: Text(selectedServer?.name ?? 'Auto-select'),
                      trailing: selectedServer?.latencyMs != null
                          ? _LatencyChip(ms: selectedServer!.latencyMs as int)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => GoRouter.of(context).go('/servers'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.lock_rounded),
                      title: const Text('Protocol'),
                      subtitle: Text(protocolLabel),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${homeVpn.stabilityPct}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      onTap: () => GoRouter.of(context).go('/connection'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right column — stats, protocol, actions
        Expanded(
          flex: 4,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 72, 24, 24),
            children: [
              const UsageMeterCard(),
              const SizedBox(height: 12),
              const ProtocolSelectorCard(),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Text(
                        'Quick actions',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: const Text('Server Selection'),
                      subtitle: const Text('Switch regions'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => GoRouter.of(context).go('/servers'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.shield_rounded),
                      title: const Text('Connection Detail'),
                      subtitle: const Text('Tunnel metrics'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => GoRouter.of(context).go('/connection'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.monitor_heart_outlined),
                      title: const Text('Diagnostics'),
                      subtitle: const Text('Readiness checks'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => GoRouter.of(context).go('/diagnostics'),
                    ),
                    if (homeVpn.errorMessage?.trim().isNotEmpty == true) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 16,
                                color: htb.HtbColors.statusError),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                homeVpn.errorMessage!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: htb.HtbColors.statusError),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Row(
                        children: [
                          Icon(Icons.data_usage_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            'Session: ${formatBytesCompact(homeVpn.sessionTransferredBytes)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatusHeadline extends StatelessWidget {
  const _StatusHeadline({
    required this.visualState,
    required this.connectPhaseLabel,
    required this.recoveryMessage,
  });

  final ConnectionVisualState visualState;
  final String? connectPhaseLabel;
  final String? recoveryMessage;

  @override
  Widget build(BuildContext context) {
    final headline = switch (visualState) {
      ConnectionVisualState.connected => 'Tunnel active',
      ConnectionVisualState.connecting =>
        connectPhaseLabel ?? 'Starting secure tunnel',
      ConnectionVisualState.reconnecting => 'Rebuilding secure path',
      ConnectionVisualState.disconnecting => 'Stopping tunnel',
      ConnectionVisualState.error => 'Tunnel needs attention',
      ConnectionVisualState.disconnected => 'Ready to protect traffic',
    };
    final subtitle = switch (visualState) {
      ConnectionVisualState.connected =>
        'Traffic is flowing through the SecureWave route.',
      ConnectionVisualState.connecting =>
        'Authenticating and bringing the tunnel online.',
      ConnectionVisualState.reconnecting =>
        recoveryMessage ?? 'Recovering after a network change.',
      ConnectionVisualState.disconnecting => 'Closing the active session.',
      ConnectionVisualState.error =>
        recoveryMessage ?? 'Diagnostics available if tunnel failed.',
      ConnectionVisualState.disconnected =>
        'Pick a region or protocol and connect when ready.',
    };

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            headline,
            key: ValueKey('${visualState}_$connectPhaseLabel'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _LatencyChip extends StatelessWidget {
  const _LatencyChip({required this.ms});

  final int ms;

  @override
  Widget build(BuildContext context) {
    final color = ms < 50
        ? htb.HtbColors.statusConnected
        : ms < 100
            ? htb.HtbColors.statusConnecting
            : htb.HtbColors.statusDisconnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        latencyLabel(ms),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
