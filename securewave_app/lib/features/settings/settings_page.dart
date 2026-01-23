import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/cards/action_card.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';
import '../../widgets/loaders/inline_banner.dart';

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
              subtitle: 'Manage preferences that sync to your SecureWave app.',
            ),
            const SizedBox(height: 8),
            const InlineBanner(
              message: 'Some preferences apply only on supported platforms and plans.',
              color: AppTheme.info,
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
                    subtitle: const Text('Connect when the app launches.'),
                    value: autoConnect,
                    onChanged: (value) => setState(() => autoConnect = value),
                  ),
                ),
                Card(
                  child: SwitchListTile(
                    title: const Text('Connection safeguard'),
                    subtitle: const Text('Pause traffic if VPN drops (where supported).'),
                    value: killSwitch,
                    onChanged: (value) => setState(() => killSwitch = value),
                  ),
                ),
                const Card(
                  child: ListTile(
                    title: Text('Connection core'),
                    subtitle: Text('SecureWave Core (managed by the app)'),
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
            const SizedBox(height: 24),
            // Version footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderDark.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppTheme.buttonGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'v${AppConstants.appVersion}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppConstants.appName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppConstants.appTagline,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
