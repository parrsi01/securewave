import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../theme/securewave_palette.dart';

class LiveTrafficChart extends ConsumerStatefulWidget {
  const LiveTrafficChart({super.key, this.height = 180});

  final double height;

  @override
  ConsumerState<LiveTrafficChart> createState() => _LiveTrafficChartState();
}

class _LiveTrafficChartState extends ConsumerState<LiveTrafficChart> {
  final List<double> _download = <double>[];
  final List<double> _upload = <double>[];

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnStateProvider, (previous, next) {
      final nextDownload = List<double>.from(_download)..add(next.dataRateDown);
      final nextUpload = List<double>.from(_upload)..add(next.dataRateUp);
      while (nextDownload.length > 24) {
        nextDownload.removeAt(0);
      }
      while (nextUpload.length > 24) {
        nextUpload.removeAt(0);
      }
      if (!mounted) return;
      setState(() {
        _download
          ..clear()
          ..addAll(nextDownload);
        _upload
          ..clear()
          ..addAll(nextUpload);
      });
    });

    final points = _download.isEmpty
        ? const <double>[0, 0]
        : _download.length == 1
            ? <double>[_download.first, _download.first]
            : _download;
    final uploads = _upload.isEmpty
        ? const <double>[0, 0]
        : _upload.length == 1
            ? <double>[_upload.first, _upload.first]
            : _upload;
    final maxY = <double>[...points, ...uploads].fold<double>(
      10,
      (current, value) => value > current ? value : current,
    );

    return SizedBox(
      height: widget.height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.25,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY <= 0 ? 1 : (maxY * 1.25) / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: SecureWavePalette.graphGrid.withValues(alpha: 0.3),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: <LineChartBarData>[
            _series(points, SecureWavePalette.graphDownload),
            _series(uploads, SecureWavePalette.graphUpload),
          ],
        ),
      ),
    );
  }

  LineChartBarData _series(List<double> values, Color color) {
    return LineChartBarData(
      spots: values
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
          .toList(growable: false),
      isCurved: true,
      barWidth: 3,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.02),
          ],
        ),
      ),
    );
  }
}
