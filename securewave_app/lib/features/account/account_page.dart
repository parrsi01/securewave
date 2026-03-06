import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';
import '../../services/external_links.dart';
import '../../ui/components/dashboard_card.dart';
import '../../ui/components/section_container.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/breakpoints.dart';
import '../../ui/theme/spacing.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    final config = ref.watch(appConfigProvider);
    final isDesktop = SecureWaveBreakpoints.isDesktop(context);

    return AdaptiveShellScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionContainer(
            title: 'Account',
            subtitle:
                'Plan summary, usage, and recovery actions designed for a compact VPN dashboard.',
            child: plan.when(
              data: (data) => _PlanSummary(plan: data),
              loading: () => const DashboardCard(
                child: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const DashboardCard(
                child: Text('Unable to load plan details right now.'),
              ),
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Subscription options',
            subtitle: 'Quick access to plan upgrades and portal management.',
            child: isDesktop
                ? Row(
                    children: [
                      Expanded(
                        child: _PlanOptionCard(
                          title: 'Free',
                          price: '5 GB included',
                          description:
                              'Best for occasional browsing and short trips.',
                          features: const [
                            '5 GB monthly data',
                            'Region auto-select',
                            'Email support'
                          ],
                          actionLabel: 'Stay on Free',
                          onAction: () => AppLogger.info('Free plan intent'),
                        ),
                      ),
                      const SizedBox(width: SecureWaveSpacing.md),
                      Expanded(
                        child: _PlanOptionCard(
                          title: 'Premium',
                          price: '\$9 / month',
                          description: 'Unlimited data with priority routing.',
                          features: const [
                            'Unlimited data',
                            'Priority servers',
                            'Priority support'
                          ],
                          actionLabel: 'Upgrade',
                          onAction: () => ref
                              .read(externalLinksProvider)
                              .openUrl(config.upgradeUrl),
                          highlight: true,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _PlanOptionCard(
                        title: 'Free',
                        price: '5 GB included',
                        description:
                            'Best for occasional browsing and short trips.',
                        features: const [
                          '5 GB monthly data',
                          'Region auto-select',
                          'Email support'
                        ],
                        actionLabel: 'Stay on Free',
                        onAction: () => AppLogger.info('Free plan intent'),
                      ),
                      const SizedBox(height: SecureWaveSpacing.md),
                      _PlanOptionCard(
                        title: 'Premium',
                        price: '\$9 / month',
                        description: 'Unlimited data with priority routing.',
                        features: const [
                          'Unlimited data',
                          'Priority servers',
                          'Priority support'
                        ],
                        actionLabel: 'Upgrade',
                        onAction: () => ref
                            .read(externalLinksProvider)
                            .openUrl(config.upgradeUrl),
                        highlight: true,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Manage',
            subtitle:
                'Open the portal to review billing, active devices, and account actions.',
            child: Column(
              children: [
                DashboardCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: const Text('Open web portal'),
                    subtitle: Text(config.portalUrl),
                    onTap: () => ref
                        .read(externalLinksProvider)
                        .openUrl(config.portalUrl),
                  ),
                ),
                const SizedBox(height: SecureWaveSpacing.md),
                const DashboardCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.devices_outlined),
                    title: Text('Manage devices'),
                    subtitle: Text(
                      'If you hit a device limit, use the portal to free a slot before reconnecting.',
                    ),
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

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current plan',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: SecureWaveSpacing.xs),
                    Text(plan.name,
                        style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
              Chip(label: Text(plan.isPremium ? 'Premium' : 'Free')),
            ],
          ),
          const SizedBox(height: SecureWaveSpacing.lg),
          Text(
            '${plan.usedGb.toStringAsFixed(1)} GB used of ${plan.dataCapGb.toStringAsFixed(0)} GB',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: SecureWaveSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: plan.usagePercent,
              minHeight: 12,
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.sm),
          Text(
            '${plan.remainingGb.toStringAsFixed(1)} GB remaining',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
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
    this.highlight = false,
  });

  final String title;
  final String price;
  final String description;
  final List<String> features;
  final String actionLabel;
  final VoidCallback onAction;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(label: Text(title)),
          const SizedBox(height: SecureWaveSpacing.md),
          Text(price, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: SecureWaveSpacing.sm),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: SecureWaveSpacing.md),
          for (final feature in features) ...[
            Row(
              children: [
                const Icon(Icons.check_rounded, size: 18),
                const SizedBox(width: SecureWaveSpacing.xs),
                Expanded(child: Text(feature)),
              ],
            ),
            const SizedBox(height: SecureWaveSpacing.xs),
          ],
          const SizedBox(height: SecureWaveSpacing.md),
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
