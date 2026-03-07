import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/services/auth_session.dart';
import '../../core/models/user_plan.dart';
import '../../core/state/app_state.dart';
import '../../services/external_links.dart';
import '../../ui/app_ui_v1.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(userPlanProvider);
    final config = ref.watch(appConfigProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'Manage your plan and keep an eye on data usage.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space4),
          plan.when(
            data: (data) => _PlanSummary(plan: data),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Text('Unable to load plan details right now.'),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Subscription options',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              if (isWide) {
                return Row(
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
                        accent: AppUIv1.surfaceMuted,
                      ),
                    ),
                    const SizedBox(width: AppUIv1.space3),
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
                        actionLabel: 'Upgrade to Premium',
                        onAction: () => ref
                            .read(externalLinksProvider)
                            .openUrl(config.upgradeUrl),
                        accent: AppUIv1.accentSoft,
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
                      'Email support'
                    ],
                    actionLabel: 'Stay on Free',
                    onAction: () => AppLogger.info('Free plan intent'),
                    accent: AppUIv1.surfaceMuted,
                  ),
                  const SizedBox(height: AppUIv1.space3),
                  _PlanOptionCard(
                    title: 'Premium',
                    price: '\$9 / month',
                    description: 'Unlimited data with priority routing.',
                    features: const [
                      'Unlimited data',
                      'Priority servers',
                      'Priority support'
                    ],
                    actionLabel: 'Upgrade to Premium',
                    onAction: () => ref
                        .read(externalLinksProvider)
                        .openUrl(config.upgradeUrl),
                    accent: AppUIv1.accentSoft,
                    highlight: true,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Devices', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          ref.watch(vpnDevicesProvider).when(
                data: (devices) => _DevicesCard(devices: devices),
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppUIv1.space4),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (_, __) => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppUIv1.space4),
                    child: Text('Unable to load device activity right now.'),
                  ),
                ),
              ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Manage account in web portal'),
              subtitle: Text(config.portalUrl),
              onTap: () =>
                  ref.read(externalLinksProvider).openUrl(config.portalUrl),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: const Text('Manage devices'),
              subtitle: const Text(
                'Open the portal to revoke old devices or resolve a device limit.',
              ),
              onTap: () =>
                  ref.read(externalLinksProvider).openUrl(config.portalUrl),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out on this device'),
              subtitle: const Text(
                'Clears the local session token and lets router protection return you to login.',
              ),
              onTap: () async {
                AppLogger.uiAction('tap_sign_out', fields: const <String, Object?>{
                  'trigger': 'AccountPage.signOut',
                });
                await ref.read(authSessionProvider).clearSession();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.devices});

  final List<Map<String, dynamic>> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppUIv1.space4),
          child: Text('No device records returned by the backend.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          children: [
            for (var index = 0; index < devices.length; index++) ...[
              _DeviceRow(device: devices[index]),
              if (index != devices.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppUIv1.space2),
                  child: Divider(height: 1),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final Map<String, dynamic> device;

  @override
  Widget build(BuildContext context) {
    final name = device['name']?.toString() ??
        device['device_name']?.toString() ??
        device['id']?.toString() ??
        'Unnamed device';
    final isActive = device['active'] == true ||
        device['is_active'] == true ||
        device['status']?.toString().toLowerCase() == 'active';
    final detail = device['platform']?.toString() ??
        device['last_seen']?.toString() ??
        (isActive ? 'Active session' : 'Inactive');

    return Row(
      children: [
        CircleAvatar(
          backgroundColor:
              (isActive ? AppUIv1.accentSoft : AppUIv1.surfaceMuted),
          child: Icon(
            Icons.devices_rounded,
            color: isActive ? AppUIv1.accentStrong : AppUIv1.inkSoft,
          ),
        ),
        const SizedBox(width: AppUIv1.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space1),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppUIv1.space2,
            vertical: AppUIv1.space1,
          ),
          decoration: BoxDecoration(
            color: (isActive ? AppUIv1.accentSoft : AppUIv1.surfaceMuted)
                .withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isActive ? 'Active' : 'Inactive',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isActive ? AppUIv1.accentStrong : AppUIv1.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final usageLabel =
        '${plan.usedGb.toStringAsFixed(1)} GB of ${plan.dataCapGb.toStringAsFixed(0)} GB';
    final remainingLabel =
        '${plan.remainingGb.toStringAsFixed(1)} GB remaining';
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppUIv1.space4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current plan',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: AppUIv1.space1),
                    Text(plan.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                Chip(
                  label: Text(plan.isPremium ? 'Premium' : 'Free'),
                  backgroundColor: (plan.isPremium
                          ? AppUIv1.accentSoft
                          : AppUIv1.surfaceMuted)
                      .withValues(alpha: 0.7),
                  labelStyle: TextStyle(
                    color:
                        plan.isPremium ? AppUIv1.accentStrong : AppUIv1.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppUIv1.space3),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppUIv1.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Data usage',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppUIv1.space2),
                Text(usageLabel, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppUIv1.space2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: plan.usagePercent,
                    minHeight: 10,
                    backgroundColor: AppUIv1.surfaceMuted,
                    color: AppUIv1.accent,
                  ),
                ),
                const SizedBox(height: AppUIv1.space2),
                Text(remainingLabel,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ],
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
    required this.accent,
    this.highlight = false,
  });

  final String title;
  final String price;
  final String description;
  final List<String> features;
  final String actionLabel;
  final VoidCallback onAction;
  final Color accent;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppUIv1.space3, vertical: AppUIv1.space1),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: AppUIv1.space3),
            Text(price, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppUIv1.space2),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppUIv1.space3),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: AppUIv1.space1),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 18,
                        color: highlight ? AppUIv1.accent : AppUIv1.inkSoft),
                    const SizedBox(width: AppUIv1.space2),
                    Expanded(
                        child: Text(feature,
                            style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppUIv1.space3),
            SizedBox(
              width: double.infinity,
              child: highlight
                  ? FilledButton(onPressed: onAction, child: Text(actionLabel))
                  : OutlinedButton(
                      onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
