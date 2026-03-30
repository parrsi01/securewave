import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/services/auth_session.dart';
import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    final config = ref.watch(appConfigProvider);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Plan summary card ─────────────────────────────────────────────
          plan.when(
            data: (data) => _PlanSummaryCard(plan: data),
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, __) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Unable to load plan details right now.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Subscription options ──────────────────────────────────────────
          Text(
            'Subscription',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          'Email support',
                        ],
                        actionLabel: 'Stay on Free',
                        onAction: () => AppLogger.info('Free plan intent'),
                        highlight: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PlanOptionCard(
                        title: 'Premium',
                        price: '\$9 / month',
                        description: 'Unlimited data with priority routing.',
                        features: const [
                          'Unlimited data',
                          'Priority servers',
                          'Priority support',
                        ],
                        actionLabel: 'Upgrade to Premium',
                        onAction: () => AppLogger.info(
                            'upgrade_intent: ${config.upgradeUrl}'),
                        highlight: true,
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _PlanOptionCard(
                    title: 'Free',
                    price: '5 GB included',
                    description:
                        'Best for occasional browsing and short trips.',
                    features: const [
                      '5 GB monthly data',
                      'Region auto-select',
                      'Email support',
                    ],
                    actionLabel: 'Stay on Free',
                    onAction: () => AppLogger.info('Free plan intent'),
                    highlight: false,
                  ),
                  const SizedBox(height: 12),
                  _PlanOptionCard(
                    title: 'Premium',
                    price: '\$9 / month',
                    description: 'Unlimited data with priority routing.',
                    features: const [
                      'Unlimited data',
                      'Priority servers',
                      'Priority support',
                    ],
                    actionLabel: 'Upgrade to Premium',
                    onAction: () =>
                        AppLogger.info('upgrade_intent: ${config.upgradeUrl}'),
                    highlight: true,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // ── Account actions ───────────────────────────────────────────────
          Text(
            'Account',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Manage account in web portal'),
                  subtitle: Text(config.portalUrl),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      AppLogger.info('portal_intent: ${config.portalUrl}'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Manage devices'),
                  subtitle: const Text(
                    'Revoke old devices or resolve a device limit.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      AppLogger.info('portal_intent: ${config.portalUrl}'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: cs.error),
                  title: Text(
                    'Sign out',
                    style: TextStyle(color: cs.error),
                  ),
                  subtitle: const Text('Clears the local session token.'),
                  onTap: () async {
                    AppLogger.info('tap_sign_out');
                    await ref.read(authSessionProvider).clearSession();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan Summary Card ─────────────────────────────────────────────────────────

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final usageLabel =
        '${plan.usedGb.toStringAsFixed(1)} / ${plan.dataCapGb.toStringAsFixed(0)} GB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(plan.isPremium ? 'Premium' : 'Free'),
                  backgroundColor: plan.isPremium
                      ? cs.primaryContainer
                      : cs.surfaceContainerHigh,
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: plan.isPremium
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data usage',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                Text(
                  usageLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: plan.usagePercent,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${plan.remainingGb.toStringAsFixed(1)} GB remaining',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan Option Card ──────────────────────────────────────────────────────────

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.description,
    required this.features,
    required this.actionLabel,
    required this.onAction,
    required this.highlight,
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (highlight) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Popular',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlight ? cs.primary : null,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: highlight ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: highlight
                  ? FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    )
                  : OutlinedButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
