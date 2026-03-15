import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/glass_panel.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';

/// VPN diagnostics screen.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        centerTitle: false,
        actions: [
          if (Theme.of(context).platform == TargetPlatform.iOS ||
              Theme.of(context).platform == TargetPlatform.macOS)
            TextButton(
              onPressed: () => context.push('/diagnostics/apple'),
              child: const Text('Apple VPN'),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          // ── Connection status ──────────────────────────────────────────
          const _SectionLabel('Connection'),
          GlassPanel(
            child: Column(
              children: [
                _DiagRow(
                  icon: Icons.circle,
                  iconColor: _statusColor(visualState),
                  label: 'Status',
                  value: _statusLabel(visualState),
                  valueColor: _statusColor(visualState),
                ),
                _divider(),
                _DiagRow(
                  icon: Icons.lock_rounded,
                  label: 'Protocol',
                  value: vpnState.effectiveProtocol?.name.toUpperCase() ?? '—',
                ),
                _divider(),
                _DiagRow(
                  icon: Icons.dns_rounded,
                  label: 'Server',
                  value: vpnState.selectedServerId ?? 'None',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space5),

          // ── Traffic ────────────────────────────────────────────────────
          const _SectionLabel('Traffic'),
          GlassPanel(
            child: Column(
              children: [
                _DiagRow(
                  icon: Icons.arrow_downward_rounded,
                  iconColor: AppColors.primaryBright,
                  label: 'Download',
                  value: formatDataRate(vpnState.dataRateDown),
                ),
                _divider(),
                _DiagRow(
                  icon: Icons.arrow_upward_rounded,
                  iconColor: AppColors.primary,
                  label: 'Upload',
                  value: formatDataRate(vpnState.dataRateUp),
                ),
                _divider(),
                _DiagRow(
                  icon: Icons.data_usage_rounded,
                  label: 'Session transferred',
                  value: formatBytesCompact(vpnState.sessionTransferredBytes),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space5),

          // ── Health ─────────────────────────────────────────────────────
          const _SectionLabel('Health'),
          GlassPanel(
            child: _DiagRow(
              icon: Icons.timeline_rounded,
              label: 'Stability',
              value: '${(vpnState.stabilityScore * 100).round()}%',
              valueColor: _stabilityColor(vpnState.stabilityScore),
            ),
          ),

          // ── Banners ────────────────────────────────────────────────────
          if (vpnState.failoverActive) ...[
            const SizedBox(height: AppSpacing.space4),
            _Banner(
              icon: Icons.swap_horiz_rounded,
              color: AppColors.warning,
              bgColor: AppColors.warningLight,
              message:
                  'Failover active: ${vpnState.failoverReason ?? 'unknown reason'}',
            ),
          ],
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.space4),
            _Banner(
              icon: Icons.error_outline_rounded,
              color: AppColors.error,
              bgColor: AppColors.errorLight,
              message: 'Error: ${vpnState.errorMessage}',
            ),
          ],
          const SizedBox(height: AppSpacing.space6),
        ],
      ),
        ),
        ),
    );
  }

  Color _statusColor(ConnectionVisualState s) {
    switch (s) {
      case ConnectionVisualState.connected:
        return AppColors.primaryBright;
      case ConnectionVisualState.connecting:
      case ConnectionVisualState.reconnecting:
        return AppColors.warning;
      case ConnectionVisualState.error:
        return AppColors.error;
      default:
        return AppColors.inkSoft;
    }
  }

  String _statusLabel(ConnectionVisualState s) {
    switch (s) {
      case ConnectionVisualState.connected:
        return 'Connected';
      case ConnectionVisualState.connecting:
        return 'Connecting…';
      case ConnectionVisualState.reconnecting:
        return 'Reconnecting…';
      case ConnectionVisualState.disconnecting:
        return 'Disconnecting…';
      case ConnectionVisualState.error:
        return 'Error';
      default:
        return 'Disconnected';
    }
  }

  Color _stabilityColor(double score) {
    if (score >= 0.8) return AppColors.primaryBright;
    if (score >= 0.5) return AppColors.warning;
    return AppColors.error;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.space2,
        bottom: AppSpacing.space2,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.inkSoft,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

Widget _divider() => const Divider(height: 1, indent: 40, endIndent: 0);

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.space3,
        horizontal: AppSpacing.space1,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: AppSpacing.iconXS,
            color: iconColor ?? AppColors.primaryBright,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: AppSpacing.iconS),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
