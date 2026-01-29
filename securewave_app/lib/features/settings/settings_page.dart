import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/adblock_state.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
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
    final protocol = ref.watch(vpnStateProvider.select((state) => state.protocol));
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
            'Adjust preferences and review diagnostics from your current device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_other),
              title: const Text('Current device'),
              subtitle: Text(deviceInfo),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Text(languageLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/language'),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Connection preferences', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto-connect'),
                  subtitle: const Text('Connect when the app opens.'),
                  value: autoConnect,
                  onChanged: (value) => setState(() => autoConnect = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Connection guard'),
                  subtitle: const Text('Pause traffic if the VPN drops where supported.'),
                  value: connectionGuard,
                  onChanged: (value) => setState(() => connectionGuard = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Column(
              children: [
                RadioListTile<VpnProtocol>(
                  title: const Text('WireGuard'),
                  subtitle: const Text('Balanced speed and privacy.'),
                  value: VpnProtocol.wireGuard,
                  groupValue: protocol,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(vpnStateProvider.notifier).selectProtocol(value);
                  },
                ),
                const Divider(height: 1),
                RadioListTile<VpnProtocol>(
                  title: const Text('IKEv2'),
                  subtitle: const Text('Reliable on mobile networks.'),
                  value: VpnProtocol.ikev2,
                  groupValue: protocol,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(vpnStateProvider.notifier).selectProtocol(value);
                  },
                ),
                const Divider(height: 1),
                RadioListTile<VpnProtocol>(
                  title: const Text('OpenVPN'),
                  subtitle: const Text('Compatibility mode.'),
                  value: VpnProtocol.openVpn,
                  groupValue: protocol,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(vpnStateProvider.notifier).selectProtocol(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Ad blocking', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          _AdblockCard(),
          const SizedBox(height: AppUIv1.space4),
          Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection readiness', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppUIv1.space2),
                  Text(
                    'Diagnostics summarize your connection health and last sync.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppUIv1.space3),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppUIv1.success),
                      const SizedBox(width: AppUIv1.space2),
                      Text('App services available', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  const SizedBox(height: AppUIv1.space2),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppUIv1.accent),
                      const SizedBox(width: AppUIv1.space2),
                      Text('Run checks after connecting', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${AppConstants.appVersion}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppUIv1.space1),
                  Text(AppConstants.appName, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppUIv1.space1),
                  Text(AppConstants.appTagline, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdblockCard extends ConsumerWidget {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Block Ads & Trackers'),
              value: adblock.blockAds,
              onChanged: (value) => ref.read(adblockStateProvider.notifier).setBlockAds(value),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Block Malware'),
              value: adblock.blockMalware,
              onChanged: (value) => ref.read(adblockStateProvider.notifier).setBlockMalware(value),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Strict mode'),
              subtitle: const Text('May block more aggressively.'),
              value: adblock.strictMode,
              onChanged: (value) => ref.read(adblockStateProvider.notifier).setStrictMode(value),
            ),
            const SizedBox(height: AppUIv1.space3),
            Text(
              'Rules: ${adblock.totalRules}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space1),
            Text(updatedLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppUIv1.space3),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: adblock.isUpdating
                    ? null
                    : () => ref.read(adblockStateProvider.notifier).updateFromRemote(),
                icon: const Icon(Icons.refresh),
                label: Text(adblock.isUpdating ? 'Updating...' : 'Update blocklist'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
