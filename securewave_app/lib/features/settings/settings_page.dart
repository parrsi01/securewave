import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../widgets/cards/action_card.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';

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
      child: ContentLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SectionHeader(
              title: 'Account & preferences',
              subtitle: 'Quick settings for your SecureWave devices.',
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
            ResponsiveWrap(
              minItemWidth: 240,
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('Auto-connect'),
                    subtitle: const Text('Connect on app launch.'),
                    value: autoConnect,
                    onChanged: (value) => setState(() => autoConnect = value),
                  ),
                ),
                Card(
                  child: SwitchListTile(
                    title: const Text('Kill switch'),
                    subtitle: const Text('Block traffic if VPN drops.'),
                    value: killSwitch,
                    onChanged: (value) => setState(() => killSwitch = value),
                  ),
                ),
                const Card(
                  child: ListTile(
                    title: Text('Protocol'),
                    subtitle: Text('WireGuard (managed by SecureWave)'),
                    trailing: Icon(Icons.shield_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ResponsiveWrap(
              minItemWidth: 180,
              children: [
                SecondaryButton(
                  label: 'Manage devices',
                  icon: Icons.devices,
                  onPressed: () => context.go('/devices'),
                ),
                SecondaryButton(
                  label: 'Run diagnostics',
                  icon: Icons.speed,
                  onPressed: () => context.go('/tests'),
                ),
                SecondaryButton(
                  label: 'VPN status',
                  icon: Icons.shield,
                  onPressed: () => context.go('/vpn'),
                ),
              ],
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
      ),
    );
  }
}
