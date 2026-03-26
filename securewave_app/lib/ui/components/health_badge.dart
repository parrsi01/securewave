import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/services/diagnostic_service.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import 'neon_button.dart';
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
    final surfaceGlow = switch (widget.validationStatus) {
      VpnValidationStatus.healthy => htb.HtbColors.glowPrimarySoft,
      VpnValidationStatus.degraded => htb.HtbColors.glowAmber,
      VpnValidationStatus.unhealthy => htb.HtbColors.glowRed,
    };

    return AnimatedContainer(
      duration: AppTokens.durationNormal,
      curve: AppTokens.curveDefault,
      padding: const EdgeInsets.all(AppSpacing.space3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.color.withValues(alpha: 0.12),
            htb.HtbColors.bg1,
            htb.HtbColors.bg3,
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: widget.color.withValues(alpha: _expanded ? 0.48 : 0.34),
          width: AppTokens.neonBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: surfaceGlow.withValues(alpha: _expanded ? 0.34 : 0.22),
            blurRadius: _expanded ? 22 : 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: AutomationKeys.healthBadgeKey,
              borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space1,
                  vertical: AppSpacing.space1,
                ),
                child: Row(
                  children: [
                    _StatusBeacon(
                      color: widget.color,
                      validationStatus: widget.validationStatus,
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AnimatedSwitcher(
                                duration: AppTokens.durationNormal,
                                child: Text(
                                  widget.label,
                                  key: ValueKey('label_${widget.label}'),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: widget.color,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.space2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.space2,
                                  vertical: AppSpacing.space1,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusFull,
                                  ),
                                  border: Border.all(
                                    color: widget.color.withValues(alpha: 0.26),
                                  ),
                                ),
                                child: Text(
                                  'VALIDATION',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: htb.HtbColors.textMono,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space1),
                          Text(
                            widget.reason?.isNotEmpty == true
                                ? widget.reason!
                                : 'Tunnel checks are currently clear.',
                            key: widget.reason != null &&
                                    widget.reason!.isNotEmpty
                                ? AutomationKeys.healthFailureReasonKey
                                : null,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.reason?.isNotEmpty == true
                                  ? widget.color
                                  : htb.HtbColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space3,
                        vertical: AppSpacing.space2,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.color.withValues(alpha: 0.12),
                            htb.HtbColors.bg0.withValues(alpha: 0.82),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                        border: Border.all(
                          color: htb.HtbColors.glassBorderDefault,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.12),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'SCORE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: htb.HtbColors.textMono,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space1),
                          Text(
                            '${widget.score}',
                            key: AutomationKeys.healthScoreKey,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: htb.HtbColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppTokens.durationNormal,
                      curve: AppTokens.curveDefault,
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: AppSpacing.iconM,
                        color: htb.HtbColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.onRetryChecks != null ||
              widget.onReconnect != null ||
              widget.onRunDiagnostic != null) ...[
            const SizedBox(height: AppSpacing.space3),
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
          AnimatedSize(
            duration: AppTokens.durationNormal,
            curve: AppTokens.curveDefault,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    key: AutomationKeys.healthDetailsPanelKey,
                    padding: const EdgeInsets.only(top: AppSpacing.space3),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      decoration: BoxDecoration(
                        color: htb.HtbColors.bg0.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                        border: Border.all(
                          color: htb.HtbColors.glassBorderDefault,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.space2,
                            runSpacing: AppSpacing.space2,
                            children: [
                              _MetricTile(
                                label: 'Latency',
                                value: widget.latencyMs != null
                                    ? '${widget.latencyMs} ms'
                                    : '—',
                                accent: widget.color,
                              ),
                              _MetricTile(
                                label: 'Packet loss',
                                value:
                                    '${(widget.packetLoss * 100).toStringAsFixed(1)}%',
                                accent: htb.HtbColors.statusConnecting,
                              ),
                              _MetricTile(
                                label: 'IP verified',
                                value: widget.ipVerified ? 'Yes' : 'No',
                                accent: widget.ipVerified
                                    ? htb.HtbColors.statusConnected
                                    : htb.HtbColors.statusConnecting,
                              ),
                              _MetricTile(
                                label: 'DNS secured',
                                value: widget.dnsOk ? 'Yes' : 'No',
                                accent: widget.dnsOk
                                    ? htb.HtbColors.statusConnected
                                    : htb.HtbColors.statusDisconnected,
                              ),
                            ],
                          ),
                          if (_lastCheckAt != null ||
                              widget.failureType != null)
                            const SizedBox(height: AppSpacing.space3),
                          if (_lastCheckAt != null)
                            _DetailRow(
                              key: AutomationKeys.healthLastCheckTimestampKey,
                              label: 'Last check',
                              value: _formatTimestamp(_lastCheckAt!),
                            ),
                          if (widget.failureType != null)
                            _DetailRow(
                              label: 'Failure type',
                              value: _failureMessage(widget.failureType),
                              valueColor: widget.color,
                            ),
                          if (_lastDiagnosticReport != null)
                            _DiagnosticSummaryPanel(
                              report: _lastDiagnosticReport!,
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

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusBeacon extends StatelessWidget {
  const _StatusBeacon({
    required this.color,
    required this.validationStatus,
  });

  final Color color;
  final VpnValidationStatus validationStatus;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<VpnValidationStatus>(validationStatus),
      tween: Tween<double>(begin: 0.82, end: 1),
      duration: AppTokens.durationXSlow,
      curve: AppTokens.curveDefault,
      builder: (context, value, _) {
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.34),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18 * value),
                blurRadius: 18 * value,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 12 + (4 * value),
              height: 12 + (4 * value),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.56),
                    blurRadius: 10 * value,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
          ),
        if (onReconnect != null)
          _ActionButton(
            key: AutomationKeys.healthReconnectButtonKey,
            label: 'Reconnect VPN',
            icon: Icons.replay_rounded,
            color: htb.HtbColors.statusDisconnected,
            isLoading: isLoading,
            onPressed: isLoading ? null : onReconnect,
          ),
        if (onRunDiagnostic != null)
          _ActionButton(
            key: AutomationKeys.healthRunDiagnosticButtonKey,
            label: 'Run Full Diagnostic',
            icon: Icons.biotech_rounded,
            color: htb.HtbColors.accentSecondary,
            isLoading: isLoading,
            onPressed: isLoading ? null : onRunDiagnostic,
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
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return NeonOutlinedButton(
      label: isLoading ? 'Working…' : label,
      icon: isLoading ? Icons.hourglass_top_rounded : icon,
      accentColor: color,
      height: 40,
      onPressed: onPressed,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.all(AppSpacing.space3),
      decoration: BoxDecoration(
        color: htb.HtbColors.bg2.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: htb.HtbColors.textMono,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
