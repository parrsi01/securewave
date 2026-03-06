import 'package:flutter/material.dart';

import 'live_traffic_chart.dart';
import 'usage_meter.dart';

class MetricsDisplay extends StatelessWidget {
  const MetricsDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 920) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: LiveTrafficChart()),
              SizedBox(width: 16),
              Expanded(child: UsageMeter()),
            ],
          );
        }
        return const Column(
          children: <Widget>[
            LiveTrafficChart(),
            SizedBox(height: 16),
            UsageMeter(),
          ],
        );
      },
    );
  }
}
