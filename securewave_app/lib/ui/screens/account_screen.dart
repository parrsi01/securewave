import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../layout/page_frame.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';

class AccountScreen extends HookConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final profile = ref.watch(userProfileProvider);
    final plan = ref.watch(userPlanProvider);
    final devices = ref.watch(deviceListProvider);
    final vpn = ref.watch(vpnStateProvider);
    final email = auth.email ?? 'No email available';

    return PageFrame(
      eyebrow: 'Account',
      title: 'Profile and subscription',
      subtitle:
          'Subscription, device slots, authenticated identity, and session actions live here without changing backend contracts.',
      child: Column(
        children: <Widget>[
          GlassPanel(
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    email.isEmpty ? '?' : email.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        email,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        profile.valueOrNull?['display_name']?.toString() ??
                            'Authenticated SecureWave account',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05),
          const SizedBox(height: 16),
          GlassPanel(
            child: plan.when(
              data: (value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Subscription',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    value.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value.isUnlimited
                        ? 'Unlimited data'
                        : '${value.usedGb.toStringAsFixed(1)} / ${value.dataCapGb.toStringAsFixed(1)} GB used',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  _InfoRow(
                    label: 'Current session',
                    value: formatBytesCompact(vpn.sessionTransferredBytes),
                  ),
                  _InfoRow(
                    label: 'Lifetime total',
                    value: formatBytesCompact(vpn.lifetimeTransferredBytes),
                  ),
                ],
              ),
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text('Subscription data unavailable.'),
            ),
          )
              .animate()
              .fadeIn(duration: 320.ms, delay: 60.ms)
              .slideY(begin: 0.05),
          const SizedBox(height: 16),
          GlassPanel(
            child: devices.when(
              data: (value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${value.total} / ${value.limit}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${value.remaining} slots remaining',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  if (value.devices.isNotEmpty)
                    _InfoRow(
                      label: 'Primary device',
                      value: value.devices.first.name ?? 'Current device',
                    ),
                  _InfoRow(
                    label: 'State',
                    value: value.devices.any((device) => device.isActive)
                        ? 'Active sessions present'
                        : 'No active sessions',
                  ),
                ],
              ),
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text('Device data unavailable.'),
            ),
          )
              .animate()
              .fadeIn(duration: 340.ms, delay: 80.ms)
              .slideY(begin: 0.05),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/edit-profile'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/devices'),
                    icon: const Icon(Icons.devices_other_outlined),
                    label: const Text('Manage devices'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey<String>(
                      AutomationKeys.accountSignOutButton,
                    ),
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 360.ms, delay: 100.ms)
              .slideY(begin: 0.05),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sign out'),
          content: const Text(
            'The client will disconnect the tunnel first, then clear the local session.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>(
                AutomationKeys.accountConfirmSignOutButton,
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await ref.read(vpnStateProvider.notifier).disconnect();
                await ref.read(authSessionProvider).clearSession();
                if (context.mounted) {
                  context.go('/login');
                }
              },
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
