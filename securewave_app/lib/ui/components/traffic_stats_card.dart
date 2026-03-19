import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(
            icon: Icons.arrow_downward_rounded,
            label: 'Download',
            value: formatDataRate(stats.down),
            color: AppColors.secondary,
          ),
          _Divider(),
          _Stat(
            icon: Icons.arrow_upward_rounded,
            label: 'Upload',
            value: formatDataRate(stats.up),
            color: AppColors.primaryBright,
          ),
          _Divider(),
          _Stat(
            icon: Icons.data_usage_rounded,
            label: 'Used',
            value: formatBytesCompact(stats.usedBytes),
            color: AppColors.darkInkMuted,
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
    return Column(
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
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: VerticalDivider(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: 1,
      ),
    );
  }
}
