import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class MetricsDisplay extends ConsumerWidget {
  const MetricsDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final show = vpn.status == VpnStatus.connected;

    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: AppAnimations.durationNormal,
      child: AnimatedSize(
        duration: AppAnimations.durationNormal,
        curve: AppAnimations.curveDefault,
        child: show
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Card(icon: Icons.arrow_downward_rounded, iconColor: AppColors.success, value: vpn.dataRateDown, label: 'Download'),
                    const SizedBox(width: AppSpacing.space4),
                    _Card(icon: Icons.arrow_upward_rounded, iconColor: AppColors.primary, value: vpn.dataRateUp, label: 'Upload'),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.iconColor, required this.value, required this.label});
  final IconData icon;
  final Color iconColor;
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: value),
                duration: AppAnimations.durationNormal,
                builder: (_, v, __) => Text(
                  '${v.toStringAsFixed(1)} Mbps',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
