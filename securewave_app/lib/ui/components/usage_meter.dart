import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../theme/securewave_palette.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';

class UsageMeter extends ConsumerWidget {
  const UsageMeter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    return plan.when(
      data: (value) {
        final percent = value.isUnlimited ? 0.18 : value.usagePercent;
        return GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Data allowance',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                value.isUnlimited
                    ? '${value.name} includes unlimited data transfer.'
                    : '${value.usedGb.toStringAsFixed(1)} GB of ${value.dataCapGb.toStringAsFixed(1)} GB used.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 14,
                  color: SecureWavePalette.mint,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _PlanStat(
                      label: 'Remaining',
                      value: value.isUnlimited
                          ? 'Unlimited'
                          : formatBytesCompact(
                              value.dataCapBytes - value.usedBytes,
                            ),
                    ),
                  ),
                  Expanded(
                    child: _PlanStat(
                      label: 'Download cap',
                      value: '${value.speedDownMbps.toStringAsFixed(0)} Mbps',
                    ),
                  ),
                  Expanded(
                    child: _PlanStat(
                      label: 'Upload cap',
                      value: '${value.speedUpMbps.toStringAsFixed(0)} Mbps',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const GlassPanel(
        child: SizedBox(
          height: 188,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Data allowance',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
              'Usage information is unavailable right now.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanStat extends StatelessWidget {
  const _PlanStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
