import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../layout/page_frame.dart';
import '../widgets/glass_panel.dart';

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final vpn = ref.watch(vpnStateProvider);
    final catalog = ref.watch(vpnProtocolCatalogProvider).valueOrNull;
    final prefsNotifier = ref.read(preferencesProvider.notifier);
    final vpnNotifier = ref.read(vpnStateProvider.notifier);
    final isApple = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };

    return PageFrame(
      eyebrow: 'Settings',
      title: 'Connection policy',
      subtitle:
          'Protocol choice, kill switch behavior, diagnostics, and account management stay local to the client surface.',
      child: Column(
        children: <Widget>[
          GlassPanel(
            child: Column(
              children: <Widget>[
                _ToggleRow(
                  title: 'Auto-connect',
                  subtitle:
                      'Reconnect when a valid authenticated session is already available.',
                  value: prefs.autoConnect,
                  onChanged: prefsNotifier.setAutoConnect,
                ),
                const Divider(height: 28),
                _ToggleRow(
                  title: 'Kill switch',
                  subtitle:
                      'Keep non-VPN traffic blocked when the tunnel drops unexpectedly.',
                  value: prefs.killSwitch,
                  onChanged: prefsNotifier.setKillSwitch,
                ),
                const Divider(height: 28),
                _ToggleRow(
                  title: 'DNS filtering',
                  subtitle:
                      'Request ad and malware blocking during profile provisioning.',
                  value: prefs.adBlockEnabled,
                  onChanged: prefsNotifier.setAdBlock,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Protocol selection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'The UI stays aligned with available protocols returned by the current backend catalog.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                SegmentedButton<VpnProtocol>(
                  showSelectedIcon: false,
                  multiSelectionEnabled: false,
                  selected: <VpnProtocol>{vpn.protocol},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    vpnNotifier.selectProtocol(selection.first);
                  },
                  segments: VpnProtocol.values
                      .map(
                        (protocol) => ButtonSegment<VpnProtocol>(
                          value: protocol,
                          enabled: protocol == VpnProtocol.auto ||
                              (catalog?.entryFor(protocol)?.isAvailable ??
                                  true),
                          label: Text(_protocolLabel(protocol)),
                          icon: Icon(_protocolIcon(protocol)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 320.ms, delay: 60.ms)
              .slideY(begin: 0.05),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              children: <Widget>[
                ListTile(
                  key: const ValueKey<String>(AutomationKeys.diagnosticsTile),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Diagnostics'),
                  subtitle: const Text(
                    'Run live health, auth, server catalog, profile, tunnel, and traffic checks.',
                  ),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  onTap: () => context.push('/diagnostics'),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Account'),
                  subtitle: const Text(
                    'Manage devices, profile details, and current subscription context.',
                  ),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  onTap: () => context.go('/account'),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_other_outlined),
                  title: const Text('Manage devices'),
                  subtitle: const Text(
                    'Inspect the device limit and active tunnel registrations.',
                  ),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                  onTap: () => context.push('/devices'),
                ),
                if (isApple) ...<Widget>[
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.developer_mode_rounded),
                    title: const Text('Apple VPN diagnostics'),
                    subtitle: const Text(
                      'Inspect Network Extension bridge state and entitlement readiness.',
                    ),
                    trailing:
                        const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    onTap: () => context.push('/diagnostics/apple'),
                  ),
                ],
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

  String _protocolLabel(VpnProtocol protocol) {
    return switch (protocol) {
      VpnProtocol.auto => 'Automatic',
      VpnProtocol.wireGuard => 'WireGuard',
      VpnProtocol.openVpn => 'OpenVPN',
      VpnProtocol.ikev2 => 'IKEv2',
    };
  }

  IconData _protocolIcon(VpnProtocol protocol) {
    return switch (protocol) {
      VpnProtocol.auto => Icons.auto_awesome_rounded,
      VpnProtocol.wireGuard => Icons.bolt_rounded,
      VpnProtocol.openVpn => Icons.hub_outlined,
      VpnProtocol.ikev2 => Icons.shield_moon_outlined,
    };
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
