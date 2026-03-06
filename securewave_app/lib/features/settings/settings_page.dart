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
import '../../ui/components/dashboard_card.dart';
import '../../ui/components/section_container.dart';
import '../../ui/components/settings_toggle.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/spacing.dart';

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

    return AdaptiveShellScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionContainer(
            title: 'Settings',
            subtitle:
                'Production controls, protocol preferences, diagnostics, and platform compatibility in one place.',
            child: DashboardCard(
              child: Wrap(
                spacing: SecureWaveSpacing.md,
                runSpacing: SecureWaveSpacing.md,
                children: [
                  _InfoPill(label: 'Device', value: deviceInfo),
                  _InfoPill(label: 'Language', value: languageLabel),
                  _InfoPill(
                    label: 'Preferred protocol',
                    value: activeProtocol == null
                        ? vpnProtocolLabel(protocol)
                        : '${vpnProtocolLabel(protocol)} • ${vpnProtocolLabel(activeProtocol)}',
                  ),
                  if (vmEnvironment.safeModeEnabled)
                    const _InfoPill(label: 'VM mode', value: 'Active'),
                ],
              ),
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Connection behavior',
            subtitle:
                'Modern VPN controls with safe defaults and best-effort recovery.',
            child: Column(
              children: [
                SettingsToggle(
                  title: 'Auto-connect',
                  subtitle:
                      'Reconnect to the last selected server after launch.',
                  value: settings.autoConnect,
                  onChanged: (value) => ref
                      .read(clientSettingsProvider.notifier)
                      .setAutoConnect(value),
                ),
                const SizedBox(height: SecureWaveSpacing.md),
                SettingsToggle(
                  title: 'Auto-reconnect',
                  subtitle:
                      'Retry with exponential backoff if the tunnel drops.',
                  value: settings.autoReconnect,
                  onChanged: (value) => ref
                      .read(clientSettingsProvider.notifier)
                      .setAutoReconnect(value),
                ),
                const SizedBox(height: SecureWaveSpacing.md),
                SettingsToggle(
                  title: 'Best-effort kill switch',
                  subtitle:
                      'Blocks SecureWave app requests until reconnect or manual disable.',
                  value: settings.bestEffortKillSwitch,
                  onChanged: (value) async {
                    await ref
                        .read(clientSettingsProvider.notifier)
                        .setBestEffortKillSwitch(value);
                    if (!value) {
                      ref.read(networkLockProvider.notifier).release();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Protocol',
            subtitle:
                'Auto mode prefers WireGuard and only offers protocols verified by this client build.',
            child: DashboardCard(
              child: Wrap(
                spacing: SecureWaveSpacing.sm,
                runSpacing: SecureWaveSpacing.sm,
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
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Utilities',
            subtitle: vmEnvironment.safeModeEnabled &&
                    vmEnvironment.reason != null
                ? vmEnvironment.reason
                : 'Extra tools for diagnostics, language, and blocklist controls.',
            child: Column(
              children: [
                _ActionCard(
                  title: 'Diagnostics',
                  subtitle: 'Run backend, route, tunnel, and traffic checks.',
                  icon: Icons.health_and_safety_rounded,
                  onTap: () => context.push('/diagnostics'),
                ),
                const SizedBox(height: SecureWaveSpacing.md),
                _ActionCard(
                  title: 'Language',
                  subtitle: 'Switch app language.',
                  icon: Icons.language_rounded,
                  onTap: () => context.push('/settings/language'),
                ),
                const SizedBox(height: SecureWaveSpacing.md),
                const _AdBlockSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdBlockSection extends ConsumerWidget {
  const _AdBlockSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adblock = ref.watch(adblockStateProvider);
    final updatedLabel = adblock.lastUpdated == null
        ? 'Not updated yet'
        : 'Last updated ${adblock.lastUpdated!.toLocal().toString().split('.').first}';

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ad blocking', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SecureWaveSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adblock.blockAds,
            onChanged: (value) =>
                ref.read(adblockStateProvider.notifier).setBlockAds(value),
            title: const Text('Block ads and trackers'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adblock.blockMalware,
            onChanged: (value) =>
                ref.read(adblockStateProvider.notifier).setBlockMalware(value),
            title: const Text('Block malware'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adblock.strictMode,
            onChanged: (value) =>
                ref.read(adblockStateProvider.notifier).setStrictMode(value),
            title: const Text('Strict mode'),
            subtitle: const Text('More aggressive filtering.'),
          ),
          const SizedBox(height: SecureWaveSpacing.md),
          Text(updatedLabel, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: SecureWaveSpacing.md),
          FilledButton.icon(
            onPressed: adblock.isUpdating
                ? null
                : () =>
                    ref.read(adblockStateProvider.notifier).updateFromRemote(),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(adblock.isUpdating ? 'Updating' : 'Update blocklist'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SecureWaveSpacing.md,
        vertical: SecureWaveSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label · $value'),
    );
  }
}
