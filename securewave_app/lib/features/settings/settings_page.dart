import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';
import '../diagnostics/connection_diagnostics_sheet.dart';

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
    final protocol = ref.watch(
      vpnStateProvider.select((state) => state.protocol),
    );
    final languageLabel = switch (language) {
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      _ => 'English',
    };

    return SwPage(
      center: false,
      child: ListView(
        children: [
          const SwSectionHeader(
            eyebrow: 'Settings',
            title: 'Control surface',
            subtitle:
                'Device preferences, honest protocol availability, diagnostics, and release posture.',
          ),
          const SizedBox(height: AppUIv1.space5),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final left = Column(
                children: [
                  SwPanel(
                    child: Column(
                      children: [
                        SwActionTile(
                          icon: Icons.devices_other_rounded,
                          title: 'Current device',
                          subtitle: deviceInfo,
                          color: AppUIv1.accentCyan,
                        ),
                        const SizedBox(height: AppUIv1.space3),
                        SwActionTile(
                          icon: Icons.language_rounded,
                          title: 'Language',
                          subtitle: languageLabel,
                          color: AppUIv1.accentTeal,
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppUIv1.inkSoft,
                          ),
                          onTap: () => context.push('/settings/language'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppUIv1.space4),
                  _ConnectionSettings(
                    autoConnect: autoConnect,
                    onAutoConnectChanged: (value) =>
                        setState(() => autoConnect = value),
                  ),
                  const SizedBox(height: AppUIv1.space4),
                  _SecurityPosture(),
                ],
              );
              final right = Column(
                children: [
                  _ProtocolSettings(protocol: protocol, ref: ref),
                  const SizedBox(height: AppUIv1.space4),
                  _DiagnosticsSettings(),
                  const SizedBox(height: AppUIv1.space4),
                  _VersionCard(),
                ],
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: AppUIv1.space4),
                    Expanded(child: right),
                  ],
                );
              }
              return Column(
                children: [
                  left,
                  const SizedBox(height: AppUIv1.space4),
                  right,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConnectionSettings extends StatelessWidget {
  const _ConnectionSettings({
    required this.autoConnect,
    required this.onAutoConnectChanged,
  });

  final bool autoConnect;
  final ValueChanged<bool> onAutoConnectChanged;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: AppUIv1.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-connect'),
            subtitle: const Text('Connect when the app opens.'),
            value: autoConnect,
            onChanged: onAutoConnectChanged,
          ),
          const SizedBox(height: AppUIv1.space3),
          const SwActionTile(
            icon: Icons.call_split_outlined,
            title: 'Split tunneling',
            subtitle:
                'Post-v1. This build routes all traffic through the tunnel.',
            color: AppUIv1.inkSoft,
            trailing: SwStatusPill(label: 'Soon', color: AppUIv1.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _ProtocolSettings extends StatelessWidget {
  const _ProtocolSettings({required this.protocol, required this.ref});

  final VpnProtocol protocol;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: AppUIv1.accentTeal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Protocol',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SwStatusPill(
                label: 'Release honest',
                color: AppUIv1.accentTeal,
                icon: Icons.verified_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space3),
          RadioGroup<VpnProtocol>(
            groupValue: protocol,
            onChanged: (value) {
              if (value == null) return;
              ref.read(vpnStateProvider.notifier).selectProtocol(value);
            },
            child: const Column(
              children: [
                _ProtocolTile(
                  title: 'WireGuard',
                  subtitle: 'Primary supported v1 tunnel path.',
                  value: VpnProtocol.wireGuard,
                  enabled: true,
                  color: AppUIv1.accentCyan,
                ),
                SizedBox(height: AppUIv1.space3),
                _ProtocolTile(
                  title: 'IKEv2',
                  subtitle: 'Hidden from release until end-to-end hardening.',
                  value: VpnProtocol.ikev2,
                  enabled: false,
                  color: AppUIv1.warning,
                ),
                SizedBox(height: AppUIv1.space3),
                _ProtocolTile(
                  title: 'OpenVPN',
                  subtitle:
                      'Blocked until provisioning and client runtime match.',
                  value: VpnProtocol.openVpn,
                  enabled: false,
                  color: AppUIv1.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolTile extends StatelessWidget {
  const _ProtocolTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.color,
  });

  final String title;
  final String subtitle;
  final VpnProtocol value;
  final bool enabled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: SwPanel(
        accent: color,
        padding: EdgeInsets.zero,
        child: RadioListTile<VpnProtocol>(
          value: value,
          enabled: enabled,
          title: Text(title),
          subtitle: Text(subtitle),
          secondary: Icon(Icons.hub_outlined, color: color),
        ),
      ),
    );
  }
}

class _SecurityPosture extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SwPanel(
      accent: AppUIv1.accentViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(title: 'Security posture'),
          SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.shield_outlined,
            title: 'Ad/malware blocking',
            subtitle: 'ON via configured DNS protections.',
            color: AppUIv1.accentTeal,
            trailing: SwStatusPill(label: 'ON', color: AppUIv1.success),
          ),
          SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.dns_outlined,
            title: 'DNS leak protection',
            subtitle: 'Best effort and platform dependent.',
            color: AppUIv1.accentCyan,
          ),
          SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.lock_outline_rounded,
            title: 'Kill switch',
            subtitle: 'Best effort. Enable OS Always-on VPN where supported.',
            color: AppUIv1.warning,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: AppUIv1.accentCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SettingHeader(title: 'Diagnostics'),
          const SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.monitor_heart_outlined,
            title: 'Connection diagnostics',
            subtitle: 'Backend, auth, profile fetch, tunnel status.',
            color: AppUIv1.accentCyan,
            trailing: const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
            onTap: () => ConnectionDiagnosticsSheet.show(context),
          ),
          const SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.radar_rounded,
            title: 'Run diagnostics',
            subtitle: 'Full readiness scan and copyable output.',
            color: AppUIv1.accentTeal,
            trailing: const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
            onTap: () => context.push('/diagnostics'),
          ),
          const SizedBox(height: AppUIv1.space3),
          SwActionTile(
            icon: Icons.warning_amber_rounded,
            title: 'Panic button',
            subtitle: 'Disconnect, clear cached tunnel profile, sign out.',
            color: AppUIv1.danger,
            trailing: const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
            onTap: () => context.push('/panic'),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: AppUIv1.inkSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${AppConstants.appVersion}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppUIv1.space1),
          Text(
            AppConstants.appName,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space1),
          Text(
            AppConstants.appTagline,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SettingHeader extends StatelessWidget {
  const _SettingHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}
