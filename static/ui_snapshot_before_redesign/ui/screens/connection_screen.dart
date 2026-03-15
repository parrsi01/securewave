import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/glass_panel.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import '../components/traffic_stats_card.dart';
import '../components/status_indicator.dart';

/// Connection detail / live stats screen.
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
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          // ── Status card ────────────────────────────────────────────
          GlassPanel(
            child: Row(
              children: [
                StatusIndicator(visualState: visualState),
                const Spacer(),
                if (vpnState.status == VpnStatus.connected)
                  _SessionTimer(connectedAt: vpnState.lastTunnelStartAt),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space4),

          // ── Traffic stats ──────────────────────────────────────────
          TrafficStatsCard(vpnState: vpnState),
          const SizedBox(height: AppSpacing.space4),

          // ── Connection details ─────────────────────────────────────
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Details',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.space4),
                if (selectedServer != null)
                  _DetailRow(
                    icon: Icons.public_rounded,
                    label: 'Server',
                    value:
                        '${selectedServer.name}${selectedServer.country != null ? ' · ${selectedServer.country}' : ''}',
                  ),
                if (vpnState.effectiveProtocol != null)
                  _DetailRow(
                    icon: Icons.lock_rounded,
                    label: 'Protocol',
                    value:
                        vpnState.effectiveProtocol!.name.toUpperCase(),
                  ),
                _DetailRow(
                  icon: Icons.data_usage_rounded,
                  label: 'Session transferred',
                  value: formatBytesCompact(
                      vpnState.sessionTransferredBytes),
                ),
                _DetailRow(
                  icon: Icons.timeline_rounded,
                  label: 'Stability',
                  value:
                      '${(vpnState.stabilityScore * 100).round()}%',
                ),
              ],
            ),
          ),

          // ── Error banner ───────────────────────────────────────────
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Container(
              padding: const EdgeInsets.all(AppSpacing.space4),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: AppSpacing.iconS),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      vpnState.errorMessage!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
        ),
        ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
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
          Icon(icon, size: AppSpacing.iconS, color: AppColors.primaryBright),
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
                ),
          ),
        ],
      ),
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
                color: AppColors.primaryBright,
                fontWeight: FontWeight.w700,
              ),
        );
      },
    );
  }
}
