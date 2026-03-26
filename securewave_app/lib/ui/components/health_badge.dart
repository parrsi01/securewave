import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/services/diagnostic_service.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import '../theme/app_tokens.dart';

// ── Failure-code → user message map ──────────────────────────────────────────

String _failureMessage(VpnValidationFailureType? type) => switch (type) {
      VpnValidationFailureType.noTunnel => 'Tunnel unavailable',
      VpnValidationFailureType.noRoute => 'No route to server',
      VpnValidationFailureType.trafficBlocked => 'Traffic blocked',
      VpnValidationFailureType.highLatency => 'High latency detected',
      VpnValidationFailureType.packetLoss => 'Packet loss detected',
      VpnValidationFailureType.dnsLeak => 'DNS not secured',
      VpnValidationFailureType.partialConnectivity => 'Partial connectivity',
      null => '',
    };

// ── Color helpers ─────────────────────────────────────────────────────────────

Color _statusColor(VpnValidationStatus status) => switch (status) {
      VpnValidationStatus.healthy => htb.HtbColors.statusConnected,
      VpnValidationStatus.degraded => htb.HtbColors.statusConnecting,
      VpnValidationStatus.unhealthy => htb.HtbColors.statusDisconnected,
    };

String _statusLabel(VpnValidationStatus status) => switch (status) {
      VpnValidationStatus.healthy => 'Healthy',
      VpnValidationStatus.degraded => 'Degraded',
      VpnValidationStatus.unhealthy => 'Unhealthy',
    };

// ── HealthBadge ───────────────────────────────────────────────────────────────

/// Compact health indicator with an expandable details panel and action buttons.
///
/// Shows only when the tunnel is active (connected/degraded status) to avoid
/// cluttering the disconnected state.
///
/// Actions:
/// - degraded  → "Retry Checks" (calls [VpnStateNotifier.retryValidation])
/// - unhealthy → "Reconnect VPN" (calls [VpnStateNotifier.forceReconnect])
///             + "Run Full Diagnostic" (calls [VpnStateNotifier.triggerDiagnostic])
class HealthBadge extends ConsumerWidget {
  const HealthBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(
      vpnStateProvider.select(
        (s) => (
          status: s.validationStatus,
          score: s.validationScore,
          latencyMs: s.validationLatencyMs,
          packetLoss: s.validationPacketLoss,
          ipVerified: s.validationIpVerified,
          dnsOk: s.validationDnsOk,
          failureType: s.validationFailureType,
        ),
      ),
    );

    final color = _statusColor(health.status);
    final label = _statusLabel(health.status);
    final reason = _failureMessage(health.failureType);
    final isHealthy = health.status == VpnValidationStatus.healthy;

    final notifier = ref.read(vpnStateProvider.notifier);

    return _HealthBadgeView(
      label: label,
      score: health.score,
      color: color,
      reason: isHealthy ? null : reason,
      latencyMs: health.latencyMs,
      packetLoss: health.packetLoss,
      ipVerified: health.ipVerified,
      dnsOk: health.dnsOk,
      failureType: health.failureType,
      validationStatus: health.status,
      onRetryChecks: health.status == VpnValidationStatus.degraded
          ? () => notifier.retryValidation()
          : null,
      onReconnect: health.status == VpnValidationStatus.unhealthy
          ? () => notifier.forceReconnect()
          : null,
      onRunDiagnostic: health.status != VpnValidationStatus.healthy
          ? () => notifier.triggerDiagnostic()
          : null,
    );
  }
}

class _HealthBadgeView extends StatefulWidget {
  const _HealthBadgeView({
    required this.label,
    required this.score,
    required this.color,
    required this.reason,
    required this.latencyMs,
    required this.packetLoss,
    required this.ipVerified,
    required this.dnsOk,
    required this.failureType,
    required this.validationStatus,
    this.onRetryChecks,
    this.onReconnect,
    this.onRunDiagnostic,
  });

  final String label;
  final int score;
  final Color color;
  final String? reason;
  final int? latencyMs;
  final double packetLoss;
  final bool ipVerified;
  final bool dnsOk;
  final VpnValidationFailureType? failureType;
  final VpnValidationStatus validationStatus;

  // Action callbacks — null means the button is not shown.
  final Future<void> Function()? onRetryChecks;
  final Future<void> Function()? onReconnect;
  final Future<DiagnosticReport> Function()? onRunDiagnostic;

  @override
  State<_HealthBadgeView> createState() => _HealthBadgeViewState();
}

class _HealthBadgeViewState extends State<_HealthBadgeView> {
  bool _expanded = false;
  bool _actionInFlight = false;
  DateTime? _lastCheckAt;
  DiagnosticReport? _lastDiagnosticReport;

  // ── Action handlers ───────────────────────────────────────────────────────

  Future<void> _handleRetryChecks() async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    try {
      await widget.onRetryChecks?.call();
      if (mounted) setState(() => _lastCheckAt = DateTime.now());
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<void> _handleReconnect() async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    try {
      await widget.onReconnect?.call();
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<void> _handleRunDiagnostic() async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    try {
      final report = await widget.onRunDiagnostic?.call();
      if (mounted && report != null) {
        setState(() {
          _lastDiagnosticReport = report;
          _lastCheckAt = report.timestamp;
          _expanded = true; // auto-expand to show results
        });
      }
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Primary badge row ─────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedContainer(
            duration: AppTokens.durationNormal,
            curve: AppTokens.curveDefault,
            key: AutomationKeys.healthBadgeKey,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space3,
              vertical: AppSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.45),
                width: AppTokens.neonBorderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing dot
                AnimatedSwitcher(
                  duration: AppTokens.durationNormal,
                  child: Container(
                    key: ValueKey(widget.validationStatus),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                AnimatedSwitcher(
                  duration: AppTokens.durationNormal,
                  child: Text(
                    widget.label,
                    key: ValueKey('label_${widget.label}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: widget.color,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  key: AutomationKeys.healthScoreKey,
                  '${widget.score}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: htb.HtbColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.space1),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: AppSpacing.iconXS,
                  color: htb.HtbColors.textTertiary,
                ),
              ],
            ),
          ),
        ),

        // ── Failure reason ────────────────────────────────────────────────
        if (widget.reason != null && widget.reason!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.space1),
          Text(
            key: AutomationKeys.healthFailureReasonKey,
            widget.reason!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: widget.color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        // ── Action buttons ─────────────────────────────────────────────────
        if (widget.onRetryChecks != null ||
            widget.onReconnect != null ||
            widget.onRunDiagnostic != null) ...[
          const SizedBox(height: AppSpacing.space2),
          _ActionRow(
            isLoading: _actionInFlight,
            onRetryChecks: widget.onRetryChecks != null
                ? () => unawaited(_handleRetryChecks())
                : null,
            onReconnect: widget.onReconnect != null
                ? () => unawaited(_handleReconnect())
                : null,
            onRunDiagnostic: widget.onRunDiagnostic != null
                ? () => unawaited(_handleRunDiagnostic())
                : null,
          ),
        ],

        // ── Expandable details panel ──────────────────────────────────────
        if (_expanded)
          Padding(
            key: AutomationKeys.healthDetailsPanelKey,
            padding: const EdgeInsets.only(top: AppSpacing.space3),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space4),
              decoration: BoxDecoration(
                color: htb.HtbColors.bg2,
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                border: Border.all(
                  color: htb.HtbColors.glassBorderDefault,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Last check timestamp ────────────────────────────────
                  if (_lastCheckAt != null) ...[
                    _DetailRow(
                      key: AutomationKeys.healthLastCheckTimestampKey,
                      label: 'Last check',
                      value: _formatTimestamp(_lastCheckAt!),
                    ),
                    const SizedBox(height: AppSpacing.space1),
                  ],

                  _DetailRow(
                    label: 'Latency',
                    value: widget.latencyMs != null
                        ? '${widget.latencyMs} ms'
                        : '—',
                  ),
                  _DetailRow(
                    label: 'Packet loss',
                    value:
                        '${(widget.packetLoss * 100).toStringAsFixed(1)}%',
                  ),
                  _DetailRow(
                    label: 'IP verified',
                    value: widget.ipVerified ? 'Yes' : 'No',
                    valueColor: widget.ipVerified
                        ? htb.HtbColors.statusConnected
                        : htb.HtbColors.statusConnecting,
                  ),
                  _DetailRow(
                    label: 'DNS secured',
                    value: widget.dnsOk ? 'Yes' : 'No',
                    valueColor: widget.dnsOk
                        ? htb.HtbColors.statusConnected
                        : htb.HtbColors.statusDisconnected,
                  ),
                  if (widget.failureType != null)
                    _DetailRow(
                      label: 'Failure type',
                      value: _failureMessage(widget.failureType),
                      valueColor: widget.color,
                    ),

                  // ── Diagnostic report (if available) ───────────────────
                  if (_lastDiagnosticReport != null)
                    _DiagnosticSummaryPanel(
                      report: _lastDiagnosticReport!,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}';
  }
}

// ── Action row widget ─────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.isLoading,
    this.onRetryChecks,
    this.onReconnect,
    this.onRunDiagnostic,
  });

  final bool isLoading;
  final VoidCallback? onRetryChecks;
  final VoidCallback? onReconnect;
  final VoidCallback? onRunDiagnostic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      alignment: WrapAlignment.center,
      children: [
        if (onRetryChecks != null)
          _ActionButton(
            key: AutomationKeys.healthRetryChecksButtonKey,
            label: 'Retry Checks',
            icon: Icons.refresh_rounded,
            color: htb.HtbColors.statusConnecting,
            isLoading: isLoading,
            onPressed: isLoading ? null : onRetryChecks,
            theme: theme,
          ),
        if (onReconnect != null)
          _ActionButton(
            key: AutomationKeys.healthReconnectButtonKey,
            label: 'Reconnect VPN',
            icon: Icons.replay_rounded,
            color: htb.HtbColors.statusDisconnected,
            isLoading: isLoading,
            onPressed: isLoading ? null : onReconnect,
            theme: theme,
          ),
        if (onRunDiagnostic != null)
          _ActionButton(
            key: AutomationKeys.healthRunDiagnosticButtonKey,
            label: 'Run Full Diagnostic',
            icon: Icons.biotech_rounded,
            color: htb.HtbColors.neonCyan,
            isLoading: isLoading,
            onPressed: isLoading ? null : onRunDiagnostic,
            theme: theme,
          ),

      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.theme,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final ThemeData theme;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusS),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        backgroundColor: color.withValues(alpha: 0.06),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          : Icon(icon, size: AppSpacing.iconXS),
      label: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: onPressed == null
              ? color.withValues(alpha: 0.4)
              : color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Diagnostic summary panel ──────────────────────────────────────────────────

class _DiagnosticSummaryPanel extends StatelessWidget {
  const _DiagnosticSummaryPanel({required this.report});

  final DiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = report.allPassed
        ? htb.HtbColors.statusConnected
        : htb.HtbColors.statusDisconnected;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report.allPassed
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: AppSpacing.iconS,
                color: color,
              ),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  key: AutomationKeys.healthDiagnosticSummaryKey,
                  report.summary,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (report.failures.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space2),
            ...report.failures.map(
              (f) => Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.space3,
                  bottom: AppSpacing.space1,
                ),
                child: Text(
                  '• $f',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: htb.HtbColors.statusDisconnected,
                  ),
                ),
              ),
            ),
          ],
          if (report.recommendations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Recommendations',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.space1),
            ...report.recommendations.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space1),
                child: Text(
                  '• $r',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── _DetailRow ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
