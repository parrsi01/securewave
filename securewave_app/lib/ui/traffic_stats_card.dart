import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'app_ui_v1.dart';

class TrafficStatsCard extends StatelessWidget {
  const TrafficStatsCard({
    super.key,
    required this.downloadLabel,
    required this.uploadLabel,
    required this.downloadPoints,
    required this.uploadPoints,
    required this.sessionUsageLabel,
    required this.lifetimeUsageLabel,
    this.note,
  });

  final String downloadLabel;
  final String uploadLabel;
  final List<double> downloadPoints;
  final List<double> uploadPoints;
  final String sessionUsageLabel;
  final String lifetimeUsageLabel;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Traffic', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppUIv1.space3),
            Row(
              children: [
                Expanded(
                    child: _Metric(
                        label: 'Download',
                        value: downloadLabel,
                        color: AppUIv1.accentStrong)),
                const SizedBox(width: AppUIv1.space3),
                Expanded(
                    child: _Metric(
                        label: 'Upload',
                        value: uploadLabel,
                        color: AppUIv1.accentSun)),
              ],
            ),
            const SizedBox(height: AppUIv1.space4),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineBarsData: [
                    _buildLine(downloadPoints, AppUIv1.accentStrong),
                    _buildLine(uploadPoints, AppUIv1.accentSun),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppUIv1.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Session $sessionUsageLabel',
                    style: Theme.of(context).textTheme.bodySmall),
                Text('Lifetime $lifetimeUsageLabel',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (note != null && note!.isNotEmpty) ...[
              const SizedBox(height: AppUIv1.space2),
              Text(
                note!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildLine(List<double> samples, Color color) {
    final values = samples.isEmpty ? <double>[0, 0, 0, 0] : samples;
    return LineChartBarData(
      isCurved: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      spots: [
        for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppUIv1.space3),
      decoration: BoxDecoration(
        color: AppUIv1.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppUIv1.space2),
          Text(
            value,
            style:
                Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
