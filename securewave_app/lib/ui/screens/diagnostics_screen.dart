import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_readiness.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

/// VPN diagnostics screen.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = ref.watch(connectionVisualStateProvider);
    final protocolCatalogAsync = ref.watch(vpnProtocolCatalogProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            key: AutomationKeys.diagnosticsRootScrollKey,
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            children: [
              _SectionLabel('Connection', isDark: isDark),
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
                      value: vpnProtocolLabel(
                        vpnState.effectiveProtocol ?? vpnState.protocol,
                      ),
                    ),
                    _divider(),
                    _DiagRow(
                      icon: Icons.dns_rounded,
                      label: 'Server',
                      value: selectedServer?.name ??
                          vpnState.selectedServerId ??
                          'Auto',
                    ),
                    _divider(),
                    _DiagRow(
                      icon: Icons.error_outline_rounded,
                      label: 'Last error code',
                      value: vpnState.readiness.lastErrorCode ?? 'None',
                      valueColor: vpnState.readiness.lastErrorCode == null
                          ? null
                          : AppColors.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
              _SectionLabel('Pipeline', isDark: isDark),
              _PipelinePanel(readiness: vpnState.readiness),
              const SizedBox(height: AppSpacing.space5),
              _SectionLabel('Traffic', isDark: isDark),
              GlassPanel(
                child: Column(
                  children: [
                    _DiagRow(
                      icon: Icons.arrow_downward_rounded,
                      iconColor: AppColors.secondary,
                      label: 'Download',
                      value: formatDataRate(vpnState.dataRateDown),
                    ),
                    _divider(),
                    _DiagRow(
                      icon: Icons.arrow_upward_rounded,
                      iconColor: AppColors.primaryBright,
                      label: 'Upload',
                      value: formatDataRate(vpnState.dataRateUp),
                    ),
                    _divider(),
                    _DiagRow(
                      icon: Icons.data_usage_rounded,
                      label: 'Session transferred',
                      value: formatBytesCompact(
                        vpnState.sessionTransferredBytes,
                      ),
                    ),
                    _divider(),
                    _DiagRow(
                      icon: Icons.timeline_rounded,
                      label: 'Stability',
                      value: '${(vpnState.stabilityScore * 100).round()}%',
                      valueColor: _stabilityColor(vpnState.stabilityScore),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
              _SectionLabel('Protocols', isDark: isDark),
              protocolCatalogAsync.when(
                loading: () => const GlassPanel(
                  child: SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, _) => GlassPanel(
                  child: Text(
                    'Protocol catalog unavailable.\n$error',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                  ),
                ),
                data: (catalog) => GlassPanel(
                  child: Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: catalog.protocols.map((entry) {
                      final available = entry.isAvailable;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space3,
                          vertical: AppSpacing.space2,
                        ),
                        decoration: BoxDecoration(
                          color: (available
                                  ? AppColors.success
                                  : AppColors.warning)
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Text(
                          '${vpnProtocolLabel(entry.protocol)}${available ? '' : ' • ${entry.reason ?? 'blocked'}'}',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: available
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
              _SectionLabel('Logs', isDark: isDark),
              _LogFeed(errorMessage: vpnState.errorMessage),
              if (vpnState.killSwitchActive) ...[
                const SizedBox(height: AppSpacing.space4),
                _Banner(
                  icon: Icons.gpp_bad_rounded,
                  color: AppColors.error,
                  bgColor: AppColors.error.withValues(alpha: 0.12),
                  message: vpnState.recoveryMessage ??
                      'Kill switch active. Traffic remains blocked.',
                ),
              ],
              if (vpnState.reconnectPending) ...[
                const SizedBox(height: AppSpacing.space4),
                _Banner(
                  icon: Icons.sync_rounded,
                  color: AppColors.warning,
                  bgColor: AppColors.warning.withValues(alpha: 0.12),
                  message: vpnState.recoveryMessage ??
                      'SecureWave is reconnecting automatically.',
                ),
              ],
              if (vpnState.failoverActive) ...[
                const SizedBox(height: AppSpacing.space4),
                _Banner(
                  icon: Icons.swap_horiz_rounded,
                  color: AppColors.warning,
                  bgColor: AppColors.warning.withValues(alpha: 0.12),
                  message:
                      'Failover active: ${vpnState.failoverReason ?? 'unknown reason'}',
                ),
              ],
              if (vpnState.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.space4),
                _Banner(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  bgColor: AppColors.error.withValues(alpha: 0.12),
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

  Color _statusColor(ConnectionVisualState state) {
    switch (state) {
      case ConnectionVisualState.connected:
        return AppColors.success;
      case ConnectionVisualState.connecting:
      case ConnectionVisualState.reconnecting:
        return AppColors.warning;
      case ConnectionVisualState.error:
        return AppColors.error;
      default:
        return AppColors.darkInkSoft;
    }
  }

  String _statusLabel(ConnectionVisualState state) {
    switch (state) {
      case ConnectionVisualState.connected:
        return 'Connected';
      case ConnectionVisualState.connecting:
        return 'Connecting';
      case ConnectionVisualState.reconnecting:
        return 'Reconnecting';
      case ConnectionVisualState.disconnecting:
        return 'Disconnecting';
      case ConnectionVisualState.error:
        return 'Error';
      default:
        return 'Disconnected';
    }
  }

  Color _stabilityColor(double score) {
    if (score >= 0.8) return AppColors.success;
    if (score >= 0.5) return AppColors.warning;
    return AppColors.error;
  }
}

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.readiness});

  final VpnReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final steps = <_PipelineStepData>[
      _PipelineStepData('LOGIN', readiness.authenticated),
      _PipelineStepData('FETCH_SERVERS', readiness.serverCatalogReady),
      _PipelineStepData('FETCH_PROFILE', readiness.profileReady),
      _PipelineStepData(
        'PROTOCOL_READY',
        readiness.backendProtocolDisabled
            ? VpnReadinessGateState.notReady
            : readiness.runtimeReady,
        subtitle: readiness.runtimeHint,
      ),
      _PipelineStepData(
        'TUNNEL_START',
        _tunnelStartState(readiness),
      ),
      _PipelineStepData('TUNNEL_ACTIVE', readiness.tunnelUp),
    ];

    return GlassPanel(
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            _PipelineStep(step: steps[index]),
            if (index < steps.length - 1) _divider(),
          ],
        ],
      ),
    );
  }

  VpnReadinessGateState _tunnelStartState(VpnReadiness readiness) {
    if (readiness.tunnelUp == VpnReadinessGateState.ready) {
      return VpnReadinessGateState.ready;
    }
    if (readiness.profileReady == VpnReadinessGateState.ready ||
        readiness.lastErrorCode == 'connect_timeout') {
      return VpnReadinessGateState.notReady;
    }
    return VpnReadinessGateState.unknown;
  }
}

class _PipelineStepData {
  const _PipelineStepData(
    this.title,
    this.state, {
    this.subtitle,
  });

  final String title;
  final VpnReadinessGateState state;
  final String? subtitle;
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({required this.step});

  final _PipelineStepData step;

  @override
  Widget build(BuildContext context) {
    final color = switch (step.state) {
      VpnReadinessGateState.ready => AppColors.success,
      VpnReadinessGateState.notReady => AppColors.warning,
      VpnReadinessGateState.unknown => AppColors.darkInkSoft,
    };
    final label = switch (step.state) {
      VpnReadinessGateState.ready => 'ready',
      VpnReadinessGateState.notReady => 'blocked',
      VpnReadinessGateState.unknown => 'pending',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (step.subtitle != null && step.subtitle!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.space1),
                    child: Text(
                      step.subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
          ),
        ],
      ),
    );
  }
}

class _LogFeed extends StatelessWidget {
  const _LogFeed({required this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: ValueListenableBuilder<List<AppLogEntry>>(
        valueListenable: AppLogger.logStream,
        builder: (context, entries, _) {
          final recent = entries.reversed.take(8).toList(growable: false);
          if (recent.isEmpty &&
              (errorMessage == null || errorMessage!.isEmpty)) {
            return Text(
              'No in-memory diagnostics logs captured yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorMessage != null && errorMessage!.isNotEmpty) ...[
                Text(
                  errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpacing.space3),
              ],
              for (final entry in recent)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _timeLabel(entry.timestamp),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Text(
                          entry.message,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _timeLabel(DateTime timestamp) {
    final local = timestamp.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {required this.isDark});

  final String title;
  final bool isDark;

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
              color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
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
                    color: AppColors.darkInkMuted,
                  ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
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
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
