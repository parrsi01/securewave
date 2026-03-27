import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';

/// Glass card showing download / upload rates and session total.
class TrafficStatsCard extends ConsumerWidget {
  const TrafficStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(
      vpnStateProvider.select(
        (state) => (
          down: state.dataRateDown,
          up: state.dataRateUp,
          usedBytes: state.sessionTransferredBytes,
        ),
      ),
    );
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space4,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.arrow_downward_rounded,
              label: 'Download',
              value: formatDataRate(stats.down),
              color: htb.HtbColors.accentPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: _Stat(
              icon: Icons.arrow_upward_rounded,
              label: 'Upload',
              value: formatDataRate(stats.up),
              color: htb.HtbColors.accentSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: _Stat(
              icon: Icons.data_usage_rounded,
              label: 'Used',
              value: formatBytesCompact(stats.usedBytes),
              color: htb.HtbColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: htb.HtbColors.bg0.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(
          color: color == htb.HtbColors.textSecondary
              ? htb.HtbColors.border
              : color.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: AppSpacing.iconS),
          const SizedBox(height: AppSpacing.space1),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
