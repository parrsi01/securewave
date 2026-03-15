import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';

class UsageMeterCard extends ConsumerWidget {
  const UsageMeterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(userPlanProvider);

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Real-time allowance and throughput limits.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.space4),
          planAsync.when(
            loading: () => const _UsageLoadingState(),
            error: (error, _) => _UsageErrorState(message: error.toString()),
            data: (plan) => _UsageContent(plan: plan),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }
}

class _UsageContent extends StatelessWidget {
  const _UsageContent({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final usagePercent = plan.usagePercent.clamp(0, 1).toDouble();
    final accentColor = usagePercent >= 0.85
        ? AppColors.error
        : usagePercent >= 0.6
            ? AppColors.warning
            : AppColors.primaryBright;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricPill(
                label: 'Plan',
                value: plan.name,
                icon: Icons.workspace_premium_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: _MetricPill(
                label: 'Down / Up',
                value:
                    '${plan.speedDownMbps.toStringAsFixed(0)} / ${plan.speedUpMbps.toStringAsFixed(0)} Mbps',
                icon: Icons.speed_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: plan.isUnlimited ? null : usagePercent,
                    strokeWidth: 8,
                    backgroundColor:
                        Theme.of(context).colorScheme.outlineVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                  Center(
                    child: Text(
                      plan.isUnlimited
                          ? 'AUTO'
                          : '${(usagePercent * 100).round()}%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.isUnlimited
                        ? 'Unlimited data'
                        : '${plan.usedGb.toStringAsFixed(1)} GB used',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    plan.isUnlimited
                        ? 'Premium tier with no monthly cap.'
                        : '${plan.remainingGb.toStringAsFixed(1)} GB remaining this cycle.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
                    child: LinearProgressIndicator(
                      value: plan.isUnlimited ? null : usagePercent,
                      minHeight: 8,
                      backgroundColor:
                          Theme.of(context).colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (plan.renewalDate != null) ...[
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Renews ${_formatRenewal(plan.renewalDate!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  String _formatRenewal(DateTime renewalDate) {
    final local = renewalDate.toLocal();
    final month = switch (local.month) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      _ => 'Dec',
    };
    return '$month ${local.day}, ${local.year}';
  }
}

class _UsageLoadingState extends StatelessWidget {
  const _UsageLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const LinearProgressIndicator(minHeight: 8),
        const SizedBox(height: AppSpacing.space4),
        Row(
          children: List.generate(
            2,
            (_) => Expanded(
              child: Container(
                height: 48,
                margin: const EdgeInsets.only(right: AppSpacing.space2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageErrorState extends StatelessWidget {
  const _UsageErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: AppSpacing.iconS,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Plan metrics unavailable.\n$message',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconS, color: AppColors.primaryBright),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
