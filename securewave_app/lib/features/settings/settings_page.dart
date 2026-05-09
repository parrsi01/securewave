import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../diagnostics/connection_diagnostics_sheet.dart';
import '../vpn/protocol_selection_panel.dart';

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
    final protocol =
        ref.watch(vpnStateProvider.select((state) => state.protocol));
    final languageLabel = switch (language) {
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      _ => 'English',
    };

    return SecurePageBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= AppUIv1.tabletBreakpoint;
            final padding = AppUIv1.pagePaddingFor(width);

            final sections = [
              _DeviceLanguageSection(
                deviceInfo: deviceInfo,
                languageLabel: languageLabel,
                onLanguageTap: () => context.push('/settings/language'),
              ),
              _ConnectionSettingsSection(
                autoConnect: autoConnect,
                onAutoConnectChanged: (value) {
                  setState(() => autoConnect = value);
                },
                protocol: protocol,
                onProtocolSelected: (value) {
                  ref.read(vpnStateProvider.notifier).selectProtocol(value);
                },
              ),
              const _SecurityPostureSection(),
              _DiagnosticsSupportSection(
                onConnectionDiagnostics: () {
                  ConnectionDiagnosticsSheet.show(context);
                },
                onRunDiagnostics: () => context.push('/diagnostics'),
                onPanic: () => context.push('/panic'),
              ),
              const _AboutSection(),
            ];

            return SingleChildScrollView(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppUIv1.contentWideMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsHeader(deviceInfo: deviceInfo),
                      const SizedBox(height: AppUIv1.space4),
                      if (isWide)
                        Wrap(
                          spacing: AppUIv1.space4,
                          runSpacing: AppUIv1.space4,
                          children: [
                            for (final section in sections)
                              SizedBox(
                                width: (AppUIv1.contentWideMaxWidth -
                                        AppUIv1.space4) /
                                    2,
                                child: section,
                              ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (final section in sections) ...[
                              section,
                              if (section != sections.last)
                                const SizedBox(height: AppUIv1.space4),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.deviceInfo});

  final String deviceInfo;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppUIv1.brandGradient,
              boxShadow: AppUIv1.glowAccent,
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: AppUIv1.background,
              size: 28,
            ),
          ),
          const SizedBox(width: AppUIv1.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  'Control preferences, protocol visibility, diagnostics, and app information.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppUIv1.space2),
                Text(deviceInfo, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceLanguageSection extends StatelessWidget {
  const _DeviceLanguageSection({
    required this.deviceInfo,
    required this.languageLabel,
    required this.onLanguageTap,
  });

  final String deviceInfo;
  final String languageLabel;
  final VoidCallback onLanguageTap;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Device',
      subtitle: 'Local presentation and device context.',
      children: [
        _SettingsActionRow(
          icon: Icons.devices_other_rounded,
          title: 'Current device',
          subtitle: deviceInfo,
        ),
        const SizedBox(height: AppUIv1.space3),
        _SettingsActionRow(
          icon: Icons.language_rounded,
          title: 'Language',
          subtitle: languageLabel,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onLanguageTap,
        ),
      ],
    );
  }
}

class _ConnectionSettingsSection extends StatelessWidget {
  const _ConnectionSettingsSection({
    required this.autoConnect,
    required this.onAutoConnectChanged,
    required this.protocol,
    required this.onProtocolSelected,
  });

  final bool autoConnect;
  final ValueChanged<bool> onAutoConnectChanged;
  final VpnProtocol protocol;
  final ValueChanged<VpnProtocol> onProtocolSelected;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Connection',
      subtitle:
          'Presentation controls only. Runtime behavior stays provider-driven.',
      children: [
        SecureSurface(
          variant: SecureSurfaceVariant.base,
          padding: const EdgeInsets.all(AppUIv1.space3),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-connect'),
            subtitle: const Text('Connect when the app opens.'),
            value: autoConnect,
            onChanged: onAutoConnectChanged,
          ),
        ),
        const SizedBox(height: AppUIv1.space4),
        Text('Protocol', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppUIv1.space2),
        ProtocolSelectionPanel(
          selectedProtocol: protocol,
          onSelect: onProtocolSelected,
        ),
        const SizedBox(height: AppUIv1.space4),
        const _SettingsActionRow(
          icon: Icons.call_split_outlined,
          title: 'Split tunneling',
          subtitle:
              'Coming soon. This build routes all traffic through the tunnel.',
          trailing: SecureStatePill(label: 'Soon', color: AppUIv1.warning),
        ),
      ],
    );
  }
}

class _SecurityPostureSection extends StatelessWidget {
  const _SecurityPostureSection();

  @override
  Widget build(BuildContext context) {
    return const _SettingsSection(
      title: 'Security',
      subtitle: 'Truthful platform-dependent protection status.',
      children: [
        _SettingsActionRow(
          icon: Icons.shield_outlined,
          title: 'DNS filtering',
          subtitle: 'Provided by tunnel profile when available',
          trailing: SecureStatePill(label: 'Profile', color: AppUIv1.accent),
        ),
        SizedBox(height: AppUIv1.space3),
        _SettingsActionRow(
          icon: Icons.dns_outlined,
          title: 'DNS leak protection',
          subtitle: 'Profile and platform dependent',
        ),
        SizedBox(height: AppUIv1.space3),
        _SettingsActionRow(
          icon: Icons.lock_outline,
          title: 'Kill switch',
          subtitle: 'Linux helper/profile dependent. Verify with diagnostics.',
        ),
      ],
    );
  }
}

class _DiagnosticsSupportSection extends StatelessWidget {
  const _DiagnosticsSupportSection({
    required this.onConnectionDiagnostics,
    required this.onRunDiagnostics,
    required this.onPanic,
  });

  final VoidCallback onConnectionDiagnostics;
  final VoidCallback onRunDiagnostics;
  final VoidCallback onPanic;

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(
      title: 'Diagnostics',
      subtitle: 'Read-only checks and safe recovery actions.',
      children: [
        _SettingsActionRow(
          icon: Icons.monitor_heart_outlined,
          title: 'Connection diagnostics',
          subtitle: 'Backend, auth, profile fetch, tunnel status',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onConnectionDiagnostics,
        ),
        const SizedBox(height: AppUIv1.space3),
        _SettingsActionRow(
          icon: Icons.bug_report_outlined,
          title: 'Run diagnostics',
          subtitle: 'Full technical check report',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onRunDiagnostics,
        ),
        const SizedBox(height: AppUIv1.space3),
        _SettingsActionRow(
          icon: Icons.warning_amber_rounded,
          iconColor: AppUIv1.warning,
          title: 'Panic button',
          subtitle: 'Disconnect, sign out, and clear cached tunnel profile',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onPanic,
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return const _SettingsSection(
      title: 'About',
      subtitle: AppConstants.appTagline,
      children: [
        _SettingsActionRow(
          icon: Icons.info_outline_rounded,
          title: 'Version ${AppConstants.appVersion}',
          subtitle: AppConstants.appName,
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space1),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppUIv1.space4),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppUIv1.accent,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 21),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppUIv1.space1),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppUIv1.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}
