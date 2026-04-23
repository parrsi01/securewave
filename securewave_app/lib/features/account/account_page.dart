import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';
import '../../services/external_links.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    final config = ref.watch(appConfigProvider);

    return SwPage(
      center: false,
      child: ListView(
        children: [
          const SwSectionHeader(
            eyebrow: 'Account',
            title: 'Plan and usage',
            subtitle:
                'Subscription status, data usage, and upgrade controls remain connected to the existing account APIs.',
          ),
          const SizedBox(height: AppUIv1.space5),
          plan.when(
            data: (data) => _PlanSummary(plan: data),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SwPanel(
              child: Text('Unable to load plan details right now.'),
            ),
          ),
          const SizedBox(height: AppUIv1.space5),
          _SubscriptionOptions(config: config, ref: ref),
          const SizedBox(height: AppUIv1.space4),
          SwActionTile(
            icon: Icons.open_in_new_rounded,
            title: 'Manage account in web portal',
            subtitle: config.portalUrl,
            color: AppUIv1.accentCyan,
            trailing: const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
            onTap: () =>
                ref.read(externalLinksProvider).openUrl(config.portalUrl),
          ),
          const SizedBox(height: AppUIv1.space6),
        ],
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final usageLabel = plan.isUnlimited
        ? '${plan.usedGb.toStringAsFixed(1)} GB used'
        : '${plan.usedGb.toStringAsFixed(1)} GB of ${plan.dataCapGb.toStringAsFixed(0)} GB';
    final remainingLabel = plan.isUnlimited
        ? 'Unlimited data'
        : '${plan.remainingGb.toStringAsFixed(1)} GB remaining';
    return SwPanel(
      accent: plan.isPremium ? AppUIv1.accentTeal : AppUIv1.accentCyan,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current plan',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppUIv1.space1),
                    Text(
                      plan.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              SwStatusPill(
                label: plan.isPremium ? 'Premium' : 'Free',
                color: plan.isPremium ? AppUIv1.accentTeal : AppUIv1.accentCyan,
                icon: plan.isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.shield_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space5),
          Text('Data usage', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppUIv1.space2),
          Text(usageLabel, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppUIv1.space3),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppUIv1.radiusFull),
            child: LinearProgressIndicator(
              value: plan.isUnlimited ? null : plan.usagePercent,
              minHeight: 9,
              backgroundColor: AppUIv1.surfaceMuted,
              color: plan.isPremium ? AppUIv1.accentTeal : AppUIv1.accentCyan,
            ),
          ),
          const SizedBox(height: AppUIv1.space2),
          Text(remainingLabel, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SubscriptionOptions extends StatelessWidget {
  const _SubscriptionOptions({required this.config, required this.ref});

  final AppConfig config;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 680;
        final cards = [
          _PlanOptionCard(
            title: 'Free',
            price: '5 GB included',
            description: 'Basic encrypted access for light usage.',
            features: const [
              '5 GB monthly data',
              'Starter region access',
              'WireGuard encryption',
              'Email support',
            ],
            actionLabel: 'Stay on Free',
            onAction: () => AppLogger.info('Free plan intent'),
            color: AppUIv1.accentCyan,
          ),
          _PlanOptionCard(
            title: 'Premium',
            price: '\$9 / month',
            description: 'Unlimited data with priority routing.',
            features: const [
              'Unlimited data',
              'All available locations',
              'Priority diagnostics',
              'Priority support',
            ],
            actionLabel: 'Upgrade to Premium',
            onAction: () =>
                ref.read(externalLinksProvider).openUrl(config.upgradeUrl),
            color: AppUIv1.accentTeal,
            highlight: true,
          ),
        ];
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppUIv1.space4),
              Expanded(child: cards[1]),
            ],
          );
        }
        return Column(
          children: [
            cards[0],
            const SizedBox(height: AppUIv1.space4),
            cards[1],
          ],
        );
      },
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.description,
    required this.features,
    required this.actionLabel,
    required this.onAction,
    required this.color,
    this.highlight = false,
  });

  final String title;
  final String price;
  final String description;
  final List<String> features;
  final String actionLabel;
  final VoidCallback onAction;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: color,
      selected: highlight,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwStatusPill(
            label: title,
            color: color,
            icon: highlight
                ? Icons.workspace_premium_rounded
                : Icons.shield_outlined,
          ),
          const SizedBox(height: AppUIv1.space4),
          Text(price, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppUIv1.space2),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppUIv1.space4),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: AppUIv1.space2),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: color),
                  const SizedBox(width: AppUIv1.space2),
                  Expanded(
                    child: Text(
                      feature,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          SizedBox(
            width: double.infinity,
            child: highlight
                ? FilledButton(onPressed: onAction, child: Text(actionLabel))
                : OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ),
        ],
      ),
    );
  }
}
