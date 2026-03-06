import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/state/adblock_state.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../core/services/vm_environment.dart';
import '../../ui/app_ui_v1.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool autoConnect = true;
  bool connectionGuard = true;

  @override
  Widget build(BuildContext context) {
    final deviceInfo = ref.watch(deviceInfoProvider);
    final language = ref.watch(preferencesProvider).language;
    final protocol =
        ref.watch(vpnStateProvider.select((state) => state.protocol));
    final vmEnvironment = ref.watch(vmEnvironmentProvider);
    final languageLabel = switch (language) {
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      _ => 'English',
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'Client preferences, protocol selection, diagnostics, and platform compatibility.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Current device'),
              subtitle: Text(deviceInfo),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Text(languageLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/language'),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: ListTile(
              leading: const Icon(Icons.health_and_safety),
              title: const Text('Diagnostics'),
              subtitle:
                  const Text('Run backend, tunnel, route, and traffic checks'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/diagnostics'),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Connection behavior',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: autoConnect,
                  onChanged: (value) => setState(() => autoConnect = value),
                  title: const Text('Auto-connect'),
                  subtitle: const Text(
                      'Reconnect to the last selected server after launch.'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: connectionGuard,
                  onChanged: (value) => setState(() => connectionGuard = value),
                  title: const Text('Connection guard'),
                  subtitle: const Text(
                      'Avoid reconnect loops and fail closed on tunnel loss.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space3),
              child: SegmentedButton<VpnProtocol>(
                segments: const [
                  ButtonSegment(
                    value: VpnProtocol.wireGuard,
                    label: Text('WireGuard'),
                  ),
                  ButtonSegment(
                    value: VpnProtocol.ikev2,
                    label: Text('IKEv2'),
                  ),
                  ButtonSegment(
                    value: VpnProtocol.openVpn,
                    label: Text('OpenVPN'),
                  ),
                ],
                selected: {protocol},
                onSelectionChanged: (selection) {
                  ref
                      .read(vpnStateProvider.notifier)
                      .selectProtocol(selection.first);
                },
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          if (vmEnvironment.safeModeEnabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Linux VM safe mode'),
                subtitle: Text(vmEnvironment.reason ??
                    'VM-safe retries and delayed startup enabled.'),
              ),
            ),
          if (vmEnvironment.safeModeEnabled)
            const SizedBox(height: AppUIv1.space4),
          Text('Ad blocking', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          const _AdblockCard(),
        ],
      ),
    );
  }
}

class _AdblockCard extends ConsumerWidget {
  const _AdblockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adblock = ref.watch(adblockStateProvider);
    final updatedLabel = adblock.lastUpdated == null
        ? 'Not updated yet'
        : 'Last updated ${adblock.lastUpdated!.toLocal().toString().split('.').first}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          children: [
            SwitchListTile(
              value: adblock.blockAds,
              onChanged: (value) =>
                  ref.read(adblockStateProvider.notifier).setBlockAds(value),
              title: const Text('Block ads and trackers'),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: adblock.blockMalware,
              onChanged: (value) => ref
                  .read(adblockStateProvider.notifier)
                  .setBlockMalware(value),
              title: const Text('Block malware'),
            ),
            const Divider(height: 1),
            SwitchListTile(
              value: adblock.strictMode,
              onChanged: (value) =>
                  ref.read(adblockStateProvider.notifier).setStrictMode(value),
              title: const Text('Strict mode'),
              subtitle: const Text(
                  'More aggressive filtering; may block more domains.'),
            ),
            const SizedBox(height: AppUIv1.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Rules ${adblock.totalRules}',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(updatedLabel,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: AppUIv1.space3),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: adblock.isUpdating
                    ? null
                    : () => ref
                        .read(adblockStateProvider.notifier)
                        .updateFromRemote(),
                icon: const Icon(Icons.refresh),
                label:
                    Text(adblock.isUpdating ? 'Updating' : 'Update blocklist'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
