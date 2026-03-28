import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/components/depth_panel.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceInfo = ref.watch(deviceInfoProvider);
    final language = ref.watch(preferencesProvider).language;
    final protocol =
        ref.watch(vpnStateProvider.select((state) => state.protocol));
    final effectiveProtocol =
        ref.watch(vpnStateProvider.select((state) => state.effectiveProtocol));

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
            'Clear device controls with explicit runtime mapping.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space4),
          DepthPanel(
            depth: PanelDepth.raised,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Current device'),
              subtitle: Text(deviceInfo),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          DepthPanel(
            depth: PanelDepth.raised,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              subtitle: Text(languageLabel),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/language'),
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          DepthPanel(
            depth: PanelDepth.floating,
            padding: EdgeInsets.zero,
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
          Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space2),
          Text(
            effectiveProtocol == null
                ? 'Preferred protocol: ${vpnProtocolLabel(protocol)}'
                : 'Preferred protocol: ${vpnProtocolLabel(protocol)} • Active: ${vpnProtocolLabel(effectiveProtocol)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppUIv1.space3),
          DepthPanel(
            depth: PanelDepth.floating,
            padding: const EdgeInsets.all(AppUIv1.space3),
            child: Wrap(
              spacing: AppUIv1.space2,
              runSpacing: AppUIv1.space2,
              children: [
                for (final protocolOption in VpnProtocol.values)
                  ChoiceChip(
                    label: Text(vpnProtocolLabel(protocolOption)),
                    selected: protocol == protocolOption,
                    onSelected: (_) => ref
                        .read(vpnStateProvider.notifier)
                        .selectProtocol(protocolOption),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'Protocol choice is applied on the next /vpn/profile request.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
