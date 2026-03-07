import 'package:flutter/material.dart';

import '../../core/state/vpn_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';

/// Glass card showing download / upload rates and session total.
class TrafficStatsCard extends StatelessWidget {
  const TrafficStatsCard({super.key, required this.vpnState});

  final VpnState vpnState;

  @override
  Widget build(BuildContext context) {
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
            value: formatDataRate(vpnState.dataRateDown),
            color: AppColors.success,
          ),
          _Divider(),
          _Stat(
            icon: Icons.arrow_upward_rounded,
            label: 'Upload',
            value: formatDataRate(vpnState.dataRateUp),
            color: AppColors.primaryBright,
          ),
          _Divider(),
          _Stat(
            icon: Icons.data_usage_rounded,
            label: 'Used',
            value: formatBytesCompact(vpnState.sessionTransferredBytes),
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
                color: Colors.white,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.darkInkSoft,
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
        color: AppColors.darkBorder,
        width: 1,
      ),
    );
  }
}
