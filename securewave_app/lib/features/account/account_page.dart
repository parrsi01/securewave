import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/user_account.dart';
import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';
import '../../services/external_links.dart';
import '../../ui/app_ui_v1.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    final account = ref.watch(currentUserProvider);
    final config = ref.watch(appConfigProvider);

    return SecurePageBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= AppUIv1.tabletBreakpoint;
            final padding = AppUIv1.pagePaddingFor(width);

            return SingleChildScrollView(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppUIv1.contentWideMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AccountHeader(config: config, account: account),
                      const SizedBox(height: AppUIv1.space4),
                      plan.when(
                        data: (data) => isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: _PlanSummary(plan: data),
                                  ),
                                  const SizedBox(width: AppUIv1.space4),
                                  Expanded(
                                    flex: 5,
                                    child: _PlanOptions(config: config),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _PlanSummary(plan: data),
                                  const SizedBox(height: AppUIv1.space4),
                                  _PlanOptions(config: config),
                                ],
                              ),
                        loading: () => const _AccountLoadingState(),
                        error: (_, __) => const _AccountErrorState(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AccountHeader extends ConsumerWidget {
  const _AccountHeader({
    required this.config,
    required this.account,
  });

  final AppConfig config;
  final AsyncValue<UserAccount> account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountEmail = account.maybeWhen(
      data: (user) => user.email.isEmpty ? 'Signed in' : user.email,
      loading: () => 'Loading signed-in account...',
      orElse: () => 'Signed-in account unavailable',
    );
    final emailVerified = account.maybeWhen(
      data: (user) => user.emailVerified,
      orElse: () => null,
    );

    return SecureSurface(
      variant: SecureSurfaceVariant.raised,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppUIv1.surfaceMuted,
              borderRadius: BorderRadius.circular(AppUIv1.radiusS),
              border: Border.all(color: AppUIv1.border),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppUIv1.accentCyan,
              size: 28,
            ),
          ),
          const SizedBox(width: AppUIv1.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  accountEmail,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (emailVerified != null) ...[
                  const SizedBox(height: AppUIv1.space2),
                  SecureStatePill(
                    label:
                        emailVerified ? 'Email verified' : 'Email unverified',
                    color: emailVerified ? AppUIv1.success : AppUIv1.warning,
                    icon: emailVerified
                        ? Icons.verified_rounded
                        : Icons.mark_email_unread_outlined,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open web portal',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () =>
                ref.read(externalLinksProvider).openUrl(config.portalUrl),
          ),
        ],
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final UserPlan plan;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final usageLabel = plan.isUnlimited
        ? '${plan.usedGb.toStringAsFixed(1)} GB used'
        : '${plan.usedGb.toStringAsFixed(1)} GB of ${plan.dataCapGb.toStringAsFixed(0)} GB';
    final remainingLabel = plan.isUnlimited
        ? 'Unlimited data'
        : '${plan.remainingGb.toStringAsFixed(1)} GB remaining';
    final usagePercent = plan.usagePercent.clamp(0, 1).toDouble();
    final renewalLabel = plan.renewalDate == null
        ? 'Renewal date unavailable'
        : 'Renews ${_formatDate(plan.renewalDate!)}';

    return SecureSurface(
      variant: SecureSurfaceVariant.raised,
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
                    Text('Current plan',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: AppUIv1.space1),
                    Text(plan.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              SecureStatePill(
                label: plan.isPremium ? 'Premium' : 'Free',
                color: plan.isPremium ? AppUIv1.accentCyan : AppUIv1.accent,
                icon: plan.isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.verified_user_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space5),
          Center(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: plan.isUnlimited ? 1 : usagePercent,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      color: plan.isUnlimited
                          ? AppUIv1.accentCyan
                          : AppUIv1.accent,
                      backgroundColor:
                          AppUIv1.surfaceMuted.withValues(alpha: 0.72),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        plan.isUnlimited
                            ? 'Unlimited'
                            : '${(usagePercent * 100).round()}%',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppUIv1.space1),
                      Text(
                        'Data usage',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space5),
          _UsageMetricRow(
            usageLabel: usageLabel,
            remainingLabel: remainingLabel,
            renewalLabel: renewalLabel,
          ),
        ],
      ),
    );
  }
}

class _UsageMetricRow extends StatelessWidget {
  const _UsageMetricRow({
    required this.usageLabel,
    required this.remainingLabel,
    required this.renewalLabel,
  });

  final String usageLabel;
  final String remainingLabel;
  final String renewalLabel;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _AccountMetric(
        icon: Icons.data_usage_rounded,
        label: 'Used',
        value: usageLabel,
      ),
      _AccountMetric(
        icon: Icons.storage_rounded,
        label: 'Remaining',
        value: remainingLabel,
      ),
      _AccountMetric(
        icon: Icons.event_repeat_rounded,
        label: 'Cycle',
        value: renewalLabel,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: AppUIv1.space3),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final tile in tiles) ...[
              Expanded(child: tile),
              if (tile != tiles.last) const SizedBox(width: AppUIv1.space3),
            ],
          ],
        );
      },
    );
  }
}

class _PlanOptions extends ConsumerWidget {
  const _PlanOptions({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _PlanOptionCard(
          title: 'Free',
          status: 'Active now',
          description: 'Free mode is available now with truthful usage limits.',
          features: const [
            'Monthly data allowance',
            'WireGuard primary protocol',
            'Linux desktop release candidate',
            'Email support',
          ],
          actionLabel: 'Stay on Free',
          onAction: () => AppLogger.info('Free plan intent'),
          color: AppUIv1.accent,
        ),
        const SizedBox(height: AppUIv1.space3),
        _PlanOptionCard(
          title: 'Premium',
          status: 'Coming soon',
          description:
              'Premium is not active in this release candidate. Updates open in the portal.',
          features: const [
            'Higher usage options when released',
            'Expanded controls when available',
            'Priority support when available',
          ],
          actionLabel: 'Premium updates',
          onAction: () =>
              ref.read(externalLinksProvider).openUrl(config.upgradeUrl),
          color: AppUIv1.accentCyan,
          highlight: true,
        ),
        const SizedBox(height: AppUIv1.space3),
        SecureSurface(
          variant: SecureSurfaceVariant.base,
          padding: const EdgeInsets.all(AppUIv1.space4),
          onTap: () =>
              ref.read(externalLinksProvider).openUrl(config.portalUrl),
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, color: AppUIv1.accent),
              const SizedBox(width: AppUIv1.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Web portal',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AppUIv1.space1),
                    Text(
                      config.portalUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppUIv1.inkSoft),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.status,
    required this.description,
    required this.features,
    required this.actionLabel,
    required this.onAction,
    required this.color,
    this.highlight = false,
  });

  final String title;
  final String status;
  final String description;
  final List<String> features;
  final String actionLabel;
  final VoidCallback onAction;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant:
          highlight ? SecureSurfaceVariant.raised : SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              SecureStatePill(label: status, color: color),
            ],
          ),
          const SizedBox(height: AppUIv1.space2),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppUIv1.space4),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: AppUIv1.space2),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 17, color: color),
                  const SizedBox(width: AppUIv1.space2),
                  Expanded(
                    child: Text(feature,
                        style: Theme.of(context).textTheme.bodySmall),
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

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        children: [
          Icon(icon, color: AppUIv1.accentCyan, size: 19),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountLoadingState extends StatelessWidget {
  const _AccountLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: EdgeInsets.all(AppUIv1.space5),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AccountErrorState extends StatelessWidget {
  const _AccountErrorState();

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.danger,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Text(
        'Unable to load plan details right now.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
