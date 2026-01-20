import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../widgets/cards/action_card.dart';
import '../../widgets/layouts/section_header.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool autoConnect = true;
  bool killSwitch = true;

  @override
  Widget build(BuildContext context) {
    final deviceInfo = ref.watch(deviceInfoProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SectionHeader(
            title: 'Account & Preferences',
            subtitle: 'These settings sync with the SecureWave app.',
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Current device'),
              subtitle: Text(deviceInfo),
              trailing: const Icon(Icons.devices_other),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Auto-connect'),
              subtitle: const Text('Connect when the app opens.'),
              value: autoConnect,
              onChanged: (value) => setState(() => autoConnect = value),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Kill switch'),
              subtitle: const Text('Block traffic if VPN disconnects.'),
              value: killSwitch,
              onChanged: (value) => setState(() => killSwitch = value),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Protocol'),
              subtitle: const Text('WireGuard (managed by SecureWave app)'),
              trailing: const Icon(Icons.shield_outlined),
            ),
          ),
          const SizedBox(height: 16),
          ActionCard(
            title: 'Manage devices',
            subtitle: 'Add, rename, or revoke access.',
            icon: Icons.devices,
            onTap: () => context.go('/devices'),
          ),
        ],
      ),
    );
  }
}
