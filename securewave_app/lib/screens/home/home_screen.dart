import 'package:flutter/material.dart';

import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/platform_notice.dart';
import 'widgets/connection_ring.dart';
import 'widgets/status_display.dart';
import 'widgets/metrics_display.dart';
import 'widgets/server_pill.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: const Column(
          children: [
            Spacer(flex: 2),
            ConnectionRing(),
            SizedBox(height: AppSpacing.space5),
            StatusDisplay(),
            SizedBox(height: AppSpacing.space5),
            MetricsDisplay(),
            Spacer(flex: 1),
            ServerPill(),
            SizedBox(height: AppSpacing.space3),
            PlatformNotice(),
            SizedBox(height: AppSpacing.space4),
          ],
        ),
      ),
    );
  }
}
