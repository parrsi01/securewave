import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';

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
    final cs = Theme.of(context).colorScheme;

    final languageLabel = switch (language) {
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      _ => 'English',
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Device ────────────────────────────────────────────────────────
          Text(
            'Device',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_rounded),
              title: const Text('Current device'),
              subtitle: Text(deviceInfo),
            ),
          ),

          const SizedBox(height: 20),

          // ── Preferences ───────────────────────────────────────────────────
          Text(
            'Preferences',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  subtitle: Text(languageLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/language'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_rounded),
                  title: const Text('Diagnostics'),
                  subtitle: const Text(
                    'Run backend, tunnel, route, and traffic checks',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/diagnostics'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Protocol ─────────────────────────────────────────────────────
          Text(
            'Protocol',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effectiveProtocol == null
                        ? 'Preferred: ${vpnProtocolLabel(protocol)}'
                        : 'Preferred: ${vpnProtocolLabel(protocol)}  •  Active: ${vpnProtocolLabel(effectiveProtocol)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                  const SizedBox(height: 8),
                  Text(
                    'Applied on the next profile request.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
