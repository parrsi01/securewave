import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/vpn_state.dart';
import '../components/connect_button.dart';
import '../components/health_badge.dart';
import '../components/htb_background.dart';
import '../components/protocol_selector_card.dart';
import '../components/status_display.dart';
import '../components/traffic_graph_card.dart';
import '../components/traffic_stats_card.dart';
import '../components/usage_meter_card.dart';
import '../design/app_animations.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import '../widgets/brand_mark.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Main dashboard.
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
        ),
      ),
    );
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
            'server_id': homeVpn.selectedServerId ?? 'auto',
          },
        );
        notifier.connect();
      }
    }

    return Scaffold(
      backgroundColor: htb.HtbColors.bg0,
      body: Stack(
        children: [
          // HTB ambient background — static, free
          const HtbBackground(),

          // Connected state overlay — subtle neon purple wash
          AnimatedContainer(
            duration: AppAnimations.durationSlow,
            curve: AppAnimations.curveDefault,
            decoration: BoxDecoration(
              gradient: isDark && isConnected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        htb.HtbColors.accentPrimaryGhost,
                        Colors.transparent,
                      ],
                    )
                  : null,
            ),
          ),

          SafeArea(
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
                      visualState: visualState,
                      protocol: homeVpn.protocol,
                      effectiveProtocol: homeVpn.effectiveProtocol,
                      connectPhaseLabel: homeVpn.connectPhaseLabel,
                      stabilityPct: homeVpn.stabilityPct,
                      recoveryMessage: homeVpn.recoveryMessage,
                      selectedServerLabel: selectedServer?.name,
                      latencyMs: selectedServer?.latencyMs,
                      showHealthBadge: isConnected,
                      onServerTap: () => context.go('/servers'),
                      onConnectTap: onConnectTap,
                    ),

                    const SizedBox(height: AppSpacing.space4),

                    // ── Stats + Side Panel ──────────────────────────────────
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            flex: 6,
                            child: Column(
                              children: <Widget>[
                                TrafficStatsCard(),
                                SizedBox(height: AppSpacing.space4),
                                TrafficGraphCard(),
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
                          const TrafficStatsCard(),
                          const SizedBox(height: AppSpacing.space4),
                          const UsageMeterCard(),
                          const SizedBox(height: AppSpacing.space4),
                          const ProtocolSelectorCard(),
                          const SizedBox(height: AppSpacing.space4),
                          const TrafficGraphCard(),
                          const SizedBox(height: AppSpacing.space4),
                          _QuickActionPanel(
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
        ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 34, textSize: 24),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Control center for connection health, routing, and diagnostics.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: htb.HtbColors.textSecondary,
                    ),
              ),
            ],
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
    )
        .animate()
        .fadeIn(
          duration: AppAnimations.pageEnter,
          curve: AppAnimations.curveEnter,
        )
        .slideY(
          begin: -0.06,
          end: 0,
          duration: AppAnimations.pageEnter,
          curve: AppAnimations.curveEnter,
        );
  }
}

// ── Connection Hero ───────────────────────────────────────────────────────────

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.visualState,
    required this.protocol,
    required this.effectiveProtocol,
    required this.connectPhaseLabel,
    required this.stabilityPct,
    required this.recoveryMessage,
    required this.selectedServerLabel,
    required this.latencyMs,
    required this.showHealthBadge,
    required this.onServerTap,
    required this.onConnectTap,
  });

  final ConnectionVisualState visualState;
  final VpnProtocol protocol;
  final VpnProtocol? effectiveProtocol;
  final String? connectPhaseLabel;
  final int stabilityPct;
  final String? recoveryMessage;
  final String? selectedServerLabel;
  final int? latencyMs;
  final bool showHealthBadge;
  final VoidCallback onServerTap;
  final VoidCallback onConnectTap;

  @override
  Widget build(BuildContext context) {
    final protocolLabel = vpnProtocolLabel(effectiveProtocol ?? protocol);

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space6,
      ),
      child: Column(
        children: [
          // ── Status indicator + banners ───────────────────────────────
          const StatusDisplay(),

          if (showHealthBadge) ...[
            const SizedBox(height: AppSpacing.space3),
            const HealthBadge(),
          ],

          const SizedBox(height: AppSpacing.space5),

          // ── Hero connect button (dominant visual) ────────────────────
          ConnectButton(
            visualState: visualState,
            connectPhaseLabel: connectPhaseLabel,
            onTap: onConnectTap,
          ),

          const SizedBox(height: AppSpacing.space5),

          // ── Status headline (animated crossfade) ─────────────────────
          AnimatedSwitcher(
            duration: AppAnimations.durationNormal,
            switchInCurve: AppAnimations.curveEnter,
            switchOutCurve: AppAnimations.curveExit,
            child: Text(
              _headlineFor(visualState, connectPhaseLabel),
              key: ValueKey('${visualState}_$connectPhaseLabel'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            _subtitleFor(visualState, recoveryMessage),
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
            stabilityPct: stabilityPct,
            onServerTap: onServerTap,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: AppAnimations.durationSurfaceEnter,
          curve: AppAnimations.curveEnter,
        )
        .slideY(
          begin: AppAnimations.surfaceSlideOffset,
          end: 0,
          duration: AppAnimations.durationSurfaceEnter,
          curve: AppAnimations.curveEnter,
        );
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

  String _subtitleFor(
    ConnectionVisualState state,
    String? recoveryMessage,
  ) =>
      switch (state) {
        ConnectionVisualState.connected =>
          'Traffic is flowing through the current SecureWave route.',
        ConnectionVisualState.connecting =>
          'Authenticating, fetching profile, and bringing the tunnel online.',
        ConnectionVisualState.reconnecting => recoveryMessage ??
            'Recovering the session after a network or region change.',
        ConnectionVisualState.disconnecting =>
          'Closing the active session and clearing route state.',
        ConnectionVisualState.error => recoveryMessage ??
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
        _InfoChip(icon: Icons.lock_rounded, label: protocolLabel),
        _InfoChip(icon: Icons.timeline_rounded, label: '$stabilityPct%'),
      ],
    );
  }

  Color _latencyColor(int ms) {
    if (ms < 50) return htb.HtbColors.statusConnected;
    if (ms < 100) return htb.HtbColors.statusConnecting;
    return htb.HtbColors.statusDisconnected;
  }
}

class _InfoChip extends StatefulWidget {
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
  State<_InfoChip> createState() => _InfoChipState();
}

class _InfoChipState extends State<_InfoChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final isHighlighted = interactive && (_hovered || _pressed);
    final scale = _pressed
        ? AppAnimations.buttonPressScale
        : _hovered
            ? AppAnimations.buttonHoverScale
            : 1.0;
    final chipChild = AnimatedContainer(
      duration: AppAnimations.durationHover,
      curve: AppAnimations.curveDefault,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: isHighlighted
            ? htb.HtbColors.glassFillLight
            : htb.HtbColors.glassFill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(
          color: isHighlighted
              ? htb.HtbColors.borderAccent
              : htb.HtbColors.glassBorderDefault,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            size: AppSpacing.iconS,
            color: widget.color ??
                (isHighlighted
                    ? htb.HtbColors.accentPrimary
                    : htb.HtbColors.accentSecondary),
          ),
          const SizedBox(width: AppSpacing.space2),
          Text(
            widget.label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isHighlighted
                      ? htb.HtbColors.textPrimary
                      : htb.HtbColors.textSecondary,
                ),
          ),
          if (interactive) ...[
            const SizedBox(width: AppSpacing.space1),
            AnimatedSlide(
              offset: isHighlighted ? const Offset(0.08, 0) : Offset.zero,
              duration: AppAnimations.durationHover,
              curve: AppAnimations.curveDefault,
              child: Icon(
                Icons.chevron_right_rounded,
                size: AppSpacing.iconXS,
                color: isHighlighted
                    ? htb.HtbColors.accentPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    if (!interactive) {
      return chipChild;
    }

    return AnimatedScale(
      scale: scale,
      duration:
          _pressed ? AppAnimations.durationPress : AppAnimations.durationHover,
      curve: AppAnimations.curveDefault,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) {
            if (_hovered == value) return;
            setState(() => _hovered = value);
          },
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return htb.HtbColors.accentPrimaryGhost;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return htb.HtbColors.accentPrimaryHover;
            }
            return Colors.transparent;
          }),
          child: chipChild,
        ),
      ),
    );
  }
}

// ── Quick Action Panel ────────────────────────────────────────────────────────

class _QuickActionPanel extends ConsumerWidget {
  const _QuickActionPanel({
    required this.onServersTap,
    required this.onConnectionTap,
    required this.onDiagnosticsTap,
  });

  final VoidCallback onServersTap;
  final VoidCallback onConnectionTap;
  final VoidCallback onDiagnosticsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panelState = ref.watch(
      vpnStateProvider.select(
        (state) => (
          sessionTransferredBytes: state.sessionTransferredBytes,
          errorMessage: state.errorMessage,
        ),
      ),
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Control Center',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                'Session: ${formatBytesCompact(panelState.sessionTransferredBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          if (panelState.errorMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              panelState.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: AppAnimations.durationSlow,
          curve: AppAnimations.curveEnter,
        )
        .slideY(
          begin: AppAnimations.surfaceSlideOffset,
          end: 0,
          duration: AppAnimations.durationSlow,
          curve: AppAnimations.curveEnter,
        );
  }
}

class _ActionButton extends StatefulWidget {
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
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _hovered || _pressed;
    final scale = _pressed
        ? AppAnimations.buttonPressScale
        : _hovered
            ? AppAnimations.buttonHoverScale
            : 1.0;

    return AnimatedScale(
      scale: scale,
      duration:
          _pressed ? AppAnimations.durationPress : AppAnimations.durationHover,
      curve: AppAnimations.curveDefault,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) {
            if (_hovered == value) return;
            setState(() => _hovered = value);
          },
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return htb.HtbColors.accentPrimaryGhost;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return htb.HtbColors.accentPrimaryHover;
            }
            return Colors.transparent;
          }),
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          child: AnimatedContainer(
            duration: AppAnimations.durationHover,
            curve: AppAnimations.curveDefault,
            padding: const EdgeInsets.all(AppSpacing.space4),
            decoration: BoxDecoration(
              color: isHighlighted ? htb.HtbColors.bg3 : htb.HtbColors.bg2,
              borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              border: Border.all(
                color: isHighlighted
                    ? htb.HtbColors.borderAccent
                    : htb.HtbColors.border,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppAnimations.durationHover,
                  curve: AppAnimations.curveDefault,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? htb.HtbColors.accentPrimaryHover
                        : htb.HtbColors.accentPrimaryGhost,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                    border: Border.all(
                      color: isHighlighted
                          ? htb.HtbColors.accentPrimary
                          : htb.HtbColors.borderAccent,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: isHighlighted
                        ? htb.HtbColors.textPrimary
                        : htb.HtbColors.accentPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isHighlighted
                                  ? htb.HtbColors.textPrimary
                                  : null,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        widget.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isHighlighted
                                  ? htb.HtbColors.textSecondary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                AnimatedSlide(
                  offset: isHighlighted ? const Offset(0.08, 0) : Offset.zero,
                  duration: AppAnimations.durationHover,
                  curve: AppAnimations.curveDefault,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: isHighlighted
                        ? htb.HtbColors.accentPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
