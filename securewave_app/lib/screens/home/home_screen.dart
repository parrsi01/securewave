import 'package:flutter/material.dart';

import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/platform_notice.dart';
import 'widgets/connection_ring.dart';
import 'widgets/metrics_display.dart';
import 'widgets/server_pill.dart';
import 'widgets/status_display.dart';

/// Home screen — v2.
///
/// Full-height layout with radial gradient hero background.
/// The connection ring floats center-top with generous breathing room.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= AppSpacing.tabletBreakpoint;

    return Stack(
      children: [
        // ── Hero radial gradient background ──────────────────────────────
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.heroGradientDark
                  : AppColors.heroGradientLight,
            ),
          ),
        ),

        // ── Content ───────────────────────────────────────────────────────
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide
                  ? AppSpacing.contentMaxWidth * 0.8
                  : AppSpacing.contentMaxWidth,
            ),
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
                SizedBox(height: AppSpacing.space6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
