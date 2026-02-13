import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/platform_notice.dart';
import 'widgets/connection_button.dart';
import 'widgets/connection_metrics.dart';
import 'widgets/connection_status.dart';
import 'widgets/quick_location_selector.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const ConnectionButton(),
                const SizedBox(height: AppSpacing.space5),
                const ConnectionStatus(),
                const SizedBox(height: AppSpacing.space5),
                const ConnectionMetrics(),
                const Spacer(flex: 1),
                const QuickLocationSelector(),
                const SizedBox(height: AppSpacing.space4),
                const PlatformNotice(),
                const SizedBox(height: AppSpacing.space4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
