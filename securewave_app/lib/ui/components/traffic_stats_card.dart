import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../theme/securewave_theme.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';
import 'live_traffic_chart.dart';

class TrafficStatsCard extends ConsumerWidget {
  const TrafficStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Traffic overview', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: SecureWaveSpacing.spaceXS),
          Text(
            'Realtime bandwidth from the active tunnel interface.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricChip(
                  label: 'Download',
                  value: formatDataRate(vpn.dataRateDown),
                  icon: Icons.south_rounded,
                  tint: context.swColors.connectionActive,
                ),
              ),
              const SizedBox(width: SecureWaveSpacing.spaceSM),
              Expanded(
                child: _MetricChip(
                  label: 'Upload',
                  value: formatDataRate(vpn.dataRateUp),
                  icon: Icons.north_rounded,
                  tint: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          const LiveTrafficChart(height: 210),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryCell(
                  label: 'Session',
                  value: formatBytesCompact(vpn.sessionTransferredBytes),
                ),
              ),
              const SizedBox(width: SecureWaveSpacing.spaceSM),
              Expanded(
                child: _SummaryCell(
                  label: 'Lifetime',
                  value: formatBytesCompact(vpn.lifetimeTransferredBytes),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: tint),
          const SizedBox(height: SecureWaveSpacing.spaceXS),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SecureWaveSpacing.spaceSM),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: SecureWaveSpacing.spaceXS),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
