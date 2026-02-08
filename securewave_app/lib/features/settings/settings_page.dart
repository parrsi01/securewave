import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_protocol.dart';
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppUIv1.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppUIv1.space5),
            children: [
              Text('Settings', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppUIv1.space2),
              Text(
                'Adjust preferences and review diagnostics from your current device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Device & Language ─────────────────────────────────
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.devices_other),
                      title: const Text('Current device'),
                      subtitle: Text(deviceInfo),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: const Text('Language'),
                      subtitle: Text(languageLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/language'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Connection ────────────────────────────────────────
              Text('Connection', style: Theme.of(context).textTheme.titleMedium),
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
                  ],
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Protocol ──────────────────────────────────────────
              Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space3),
              Card(
                child: RadioGroup<VpnProtocol>(
                  groupValue: protocol,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(vpnStateProvider.notifier).selectProtocol(value);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<VpnProtocol>(
                        title: Text('WireGuard'),
                        subtitle: Text('Balanced speed and privacy.'),
                        value: VpnProtocol.wireGuard,
                      ),
                      Divider(height: 1),
                      RadioListTile<VpnProtocol>(
                        title: Text('IKEv2'),
                        subtitle: Text('Unavailable — not yet implemented.'),
                        value: VpnProtocol.ikev2,
                        enabled: false,
                      ),
                      Divider(height: 1),
                      RadioListTile<VpnProtocol>(
                        title: Text('OpenVPN'),
                        subtitle: Text('Unavailable — not yet implemented.'),
                        value: VpnProtocol.openVpn,
                        enabled: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Split tunneling ──────────────────────────────────
              Text('Split tunneling',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space2),
              Text(
                'Choose which traffic should bypass the VPN (not yet supported).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppUIv1.space3),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.call_split_outlined),
                  title: Text('Split tunneling'),
                  subtitle: Text('Coming soon. This build routes all traffic through the tunnel.'),
                  trailing: Chip(label: Text('Soon')),
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Security posture ──────────────────────────────────
              Text('Security', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space2),
              Text(
                'Always-on protections applied when the VPN is connected.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppUIv1.space3),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.shield_outlined),
                      title: Text('Ad/Malware blocking'),
                      subtitle: Text('ON (via DNS)'),
                      trailing: Chip(label: Text('ON')),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.dns_outlined),
                      title: Text('DNS leak protection'),
                      subtitle: Text('Best effort (platform dependent)'),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Kill switch'),
                      subtitle: Text('Best effort. Enable Always-on VPN where supported.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Diagnostics & About ───────────────────────────────
              Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space3),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.monitor_heart_outlined),
                      title: const Text('Run diagnostics'),
                      subtitle: const Text('Backend reachability, auth, profile fetch, native tunnel'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/diagnostics'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: AppUIv1.warning),
                      title: const Text('Panic button'),
                      subtitle: const Text('Disconnect, sign out, and clear cached tunnel profile'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/panic'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppUIv1.space3),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppUIv1.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version ${AppConstants.appVersion}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppUIv1.space1),
                      Text(AppConstants.appName,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppUIv1.space1),
                      Text(AppConstants.appTagline,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppUIv1.space5),
            ],
          ),
        ),
      ),
    );
  }
}
