import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../theme/spacing.dart';
import 'dashboard_card.dart';

class TrafficCard extends StatelessWidget {
  const TrafficCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    required this.icon,
    this.points = const <double>[],
    this.caption,
  });

  final String label;
  final String value;
  final Color accent;
  final IconData icon;
  final List<double> points;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final values = points.isEmpty ? const <double>[0, 0, 0, 0] : points;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: SecureWaveSpacing.sm),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: SecureWaveSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: SecureWaveTokens.ink,
                ),
          ),
          const SizedBox(height: SecureWaveSpacing.sm),
          SizedBox(
            height: 52,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    color: accent,
                    isCurved: true,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    spots: [
                      for (var index = 0; index < values.length; index++)
                        FlSpot(index.toDouble(), values[index]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: SecureWaveSpacing.sm),
            Text(
              caption!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SecureWaveTokens.inkMuted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
