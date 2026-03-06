import 'package:flutter/material.dart';

import 'app_ui_v1.dart';

class UsageMeter extends StatelessWidget {
  const UsageMeter({
    super.key,
    required this.label,
    required this.usagePercent,
    required this.caption,
  });

  final String label;
  final double usagePercent;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppUIv1.space3),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: usagePercent.clamp(0, 1),
                minHeight: 14,
                backgroundColor: AppUIv1.surfaceMuted,
                color: usagePercent >= 0.85
                    ? AppUIv1.warning
                    : AppUIv1.accentStrong,
              ),
            ),
            const SizedBox(height: AppUIv1.space2),
            Text(caption, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
