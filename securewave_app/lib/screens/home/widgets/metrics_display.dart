import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Metrics display — v2.
///
/// Glass-effect cards for download/upload speed.
/// Slides in smoothly when connected, collapses when not.
class MetricsDisplay extends ConsumerWidget {
  const MetricsDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(
      vpnStateProvider.select((s) => s.status == VpnStatus.connected),
    );
    final rates = ref.watch(
      vpnStateProvider.select((s) => (
            down: s.dataRateDown,
            up: s.dataRateUp,
            sessionBytes: s.sessionTransferredBytes,
          )),
    );
    final sessionMb = rates.sessionBytes / 1024 / 1024;

    return AnimatedSize(
      duration: AppAnimations.durationMedium,
      curve: AppAnimations.curveDefault,
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: AppAnimations.durationNormal,
        child: show
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RepaintBoundary(
                        child: _MetricCard(
                          icon: Icons.arrow_downward_rounded,
                          iconColor: AppColors.success,
                          value: rates.down,
                          label: 'Download',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: RepaintBoundary(
                        child: _MetricCard(
                          icon: Icons.arrow_upward_rounded,
                          iconColor: AppColors.primary,
                          value: rates.up,
                          label: 'Upload',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: RepaintBoundary(
                        child: _MetricCard(
                          icon: Icons.data_usage_rounded,
                          iconColor: AppColors.secondary,
                          value: sessionMb,
                          label: 'Session',
                          unit: 'MB',
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(height: 0),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.unit = 'Mbps',
  });

  final IconData icon;
  final Color iconColor;
  final double value;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withValues(alpha: 0.80)
            : AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]
            : [
                BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: value),
                  duration: AppAnimations.durationNormal,
                  curve: AppAnimations.curveDefault,
                  builder: (_, v, __) => Text(
                    '${v.toStringAsFixed(1)} $unit',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
