import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';

class TrafficGraphCard extends HookConsumerWidget {
  const TrafficGraphCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final history = useState<List<_TrafficSample>>(
      const <_TrafficSample>[
        _TrafficSample(down: 0, up: 0),
      ],
    );

    useEffect(() {
      final next = <_TrafficSample>[
        ...history.value,
        _TrafficSample(
          down: vpnState.dataRateDown.clamp(0, 4000).toDouble(),
          up: vpnState.dataRateUp.clamp(0, 4000).toDouble(),
        ),
      ];
      if (next.length > 18) {
        next.removeRange(0, next.length - 18);
      }
      history.value = next;
      return null;
    }, <Object?>[
      vpnState.status,
      vpnState.dataRateDown,
      vpnState.dataRateUp,
    ]);

    final samples = history.value;
    final peak = samples.fold<double>(
      10,
      (current, sample) => [
        current,
        sample.down,
        sample.up,
      ].reduce((a, b) => a > b ? a : b),
    );

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Traffic',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                'Peak ${formatDataRate(peak)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Recent download and upload samples from the live tunnel.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.space4),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: peak <= 0 ? 10 : peak * 1.15,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: peak <= 60 ? 10 : peak / 4,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.45),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: peak <= 60 ? 10 : peak / 4,
                      getTitlesWidget: (value, meta) => Text(
                        value >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}G'
                            : value.toStringAsFixed(0),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 4,
                      getTitlesWidget: (value, meta) {
                        final label = (samples.length - 1 - value.toInt()).abs();
                        return Text(
                          label == 0 ? 'now' : '-${label}s',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  _series(
                    context: context,
                    color: AppColors.secondary,
                    values: samples.map((sample) => sample.down).toList(),
                  ),
                  _series(
                    context: context,
                    color: AppColors.primaryBright,
                    values: samples.map((sample) => sample.up).toList(),
                  ),
                ],
              ),
              duration: 250.ms,
              curve: Curves.easeOutCubic,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            children: [
              _LegendPill(
                color: AppColors.secondary,
                label: 'Download ${formatDataRate(vpnState.dataRateDown)}',
              ),
              _LegendPill(
                color: AppColors.primaryBright,
                label: 'Upload ${formatDataRate(vpnState.dataRateUp)}',
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 340.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }

  LineChartBarData _series({
    required BuildContext context,
    required Color color,
    required List<double> values,
  }) {
    return LineChartBarData(
      spots: [
        for (var index = 0; index < values.length; index++)
          FlSpot(index.toDouble(), values[index]),
      ],
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TrafficSample {
  const _TrafficSample({
    required this.down,
    required this.up,
  });

  final double down;
  final double up;
}
