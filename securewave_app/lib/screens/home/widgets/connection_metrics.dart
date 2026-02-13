import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class ConnectionMetrics extends ConsumerWidget {
  const ConnectionMetrics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final isConnected = vpn.status == VpnStatus.connected;

    return AnimatedOpacity(
      opacity: isConnected ? 1.0 : 0.0,
      duration: AppAnimations.durationNormal,
      curve: AppAnimations.curveDefault,
      child: IgnorePointer(
        ignoring: !isConnected,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MetricTile(
              icon: Icons.arrow_downward_rounded,
              value: '${vpn.dataRateDown.toStringAsFixed(1)} Mbps',
              iconColor: AppColors.success,
            ),
            const SizedBox(width: AppSpacing.space6),
            _MetricTile(
              icon: Icons.arrow_upward_rounded,
              value: '${vpn.dataRateUp.toStringAsFixed(1)} Mbps',
              iconColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: AppSpacing.space1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
