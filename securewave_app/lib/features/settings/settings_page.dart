import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/services/vm_environment.dart';
import '../../core/state/adblock_state.dart';
import '../../core/state/app_state.dart';
import '../../core/state/client_settings_state.dart';
import '../../core/state/network_lock_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceInfo = ref.watch(deviceInfoProvider);
    final language = ref.watch(preferencesProvider).language;
    final protocol =
        ref.watch(vpnStateProvider.select((state) => state.protocol));
    final activeProtocol =
        ref.watch(vpnStateProvider.select((state) => state.activeProtocol));
    final settings = ref.watch(clientSettingsProvider);
    final vmEnvironment = ref.watch(vmEnvironmentProvider);
    final supportedProtocols = ref.watch(vpnServiceProvider).supportedProtocols;

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
            'Clear device controls with explicit runtime mapping. Server and protocol choices are the only settings sent back to the VPN backend.',
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
          Text('Device controls',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Column(
              children: [
                _MappedSwitchTile(
                  value: settings.autoConnect,
                  onChanged: (value) => ref
                      .read(clientSettingsProvider.notifier)
                      .setAutoConnect(value),
                  title: const Text('Auto-connect'),
                  subtitle: const Text('Restores the last wanted connection on this device.'),
                  mappingLabel: 'Client restore',
                ),
                const Divider(height: 1),
                _MappedSwitchTile(
                  value: settings.autoReconnect,
                  onChanged: (value) => ref
                      .read(clientSettingsProvider.notifier)
                      .setAutoReconnect(value),
                  title: const Text('Auto-reconnect'),
                  subtitle: const Text('Uses the VPN state machine retry path after unexpected tunnel drops.'),
                  mappingLabel: 'State machine',
                ),
                const Divider(height: 1),
                _MappedSwitchTile(
                  value: settings.bestEffortKillSwitch,
                  onChanged: (value) async {
                    await ref
                        .read(clientSettingsProvider.notifier)
                        .setBestEffortKillSwitch(value);
                    if (!value) {
                      ref.read(networkLockProvider.notifier).release();
                    }
                  },
                  title: const Text('Best-effort kill switch'),
                  subtitle: const Text('Pauses SecureWave app requests locally until reconnect or manual disable.'),
                  mappingLabel: 'App network lock',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space2),
          Text(
            activeProtocol == null
                ? 'Preferred protocol: ${vpnProtocolLabel(protocol)}'
                : 'Preferred protocol: ${vpnProtocolLabel(protocol)} • Active: ${vpnProtocolLabel(activeProtocol)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space3),
              child: Wrap(
                spacing: AppUIv1.space2,
                runSpacing: AppUIv1.space2,
                children: [
                  for (final protocolOption in VpnProtocol.values)
                    ChoiceChip(
                      label: Text(vpnProtocolLabel(protocolOption)),
                      selected: protocol == protocolOption,
                      onSelected: protocolOption == VpnProtocol.auto ||
                              supportedProtocols.contains(protocolOption)
                          ? (_) => ref
                              .read(vpnStateProvider.notifier)
                              .selectProtocol(protocolOption)
                          : null,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'Protocol choice is applied on the next `/vpn/profile` request. This build only enables protocols the client can verify natively.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!supportedProtocols.contains(VpnProtocol.ikev2) ||
              !supportedProtocols.contains(VpnProtocol.openVpn))
            Padding(
              padding: const EdgeInsets.only(top: AppUIv1.space2),
              child: Text(
                'WireGuard is currently the verified native tunnel in this build, so Auto prefers WireGuard first.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: AppUIv1.space4),
          if (vmEnvironment.safeModeEnabled)
            Card(
              child: ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Linux VM safe mode'),
                subtitle: Text(vmEnvironment.reason ??
                    'Virtualization detected. Routing and DNS checks are hardened.'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppUIv1.space2,
                    vertical: AppUIv1.space1,
                  ),
                  decoration: BoxDecoration(
                    color: AppUIv1.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('ACTIVE'),
                ),
              ),
            ),
          if (vmEnvironment.safeModeEnabled)
            const SizedBox(height: AppUIv1.space4),
          Text('Tunnel filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'These switches are pushed through the native adblock bridge on this device. They are not stored by the backend API.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
            _MappedSwitchTile(
              value: adblock.blockAds,
              onChanged: (value) =>
                  ref.read(adblockStateProvider.notifier).setBlockAds(value),
              title: const Text('Block ads and trackers'),
              mappingLabel: 'Native bridge',
            ),
            const Divider(height: 1),
            _MappedSwitchTile(
              value: adblock.blockMalware,
              onChanged: (value) => ref
                  .read(adblockStateProvider.notifier)
                  .setBlockMalware(value),
              title: const Text('Block malware'),
              mappingLabel: 'Native bridge',
            ),
            const Divider(height: 1),
            _MappedSwitchTile(
              value: adblock.strictMode,
              onChanged: (value) =>
                  ref.read(adblockStateProvider.notifier).setStrictMode(value),
              title: const Text('Strict mode'),
              subtitle: const Text(
                  'More aggressive filtering; may block more domains.'),
              mappingLabel: 'Native bridge',
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

class _MappedSwitchTile extends StatelessWidget {
  const _MappedSwitchTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.mappingLabel,
    this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget? subtitle;
  final String mappingLabel;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(child: title),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppUIv1.space2,
              vertical: AppUIv1.space1,
            ),
            decoration: BoxDecoration(
              color: AppUIv1.accentSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              mappingLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppUIv1.accentStrong,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
      subtitle: subtitle,
    );
  }
}
