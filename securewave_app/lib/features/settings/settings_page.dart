import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/app_state.dart';
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
