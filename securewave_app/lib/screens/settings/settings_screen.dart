import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/config/app_config.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_protocol_catalog.dart';
import '../../core/models/vpn_status.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/vpn_state.dart';
import '../../core/utils/api_error.dart';
import '../../core/vpn/protocol_capabilities.dart';
import '../../features/onboarding/feedback_sheet.dart';
import '../../services/api_client.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Settings screen — v2.
///
/// Clean grouped sections with card containers.
/// Toggle cards with icon badges. Protocol selector as pill cards.
/// Diagnostics as animated slide-in panel.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _diagExpanded = false;
  List<_DiagResult>? _diagResults;
  bool _diagRunning = false;
  bool _reconnecting = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedProtocol =
        ref.watch(vpnStateProvider.select((s) => s.protocol));
    final vpnStatus = ref.watch(vpnStateProvider.select((s) => s.status));
    final vpnBusy = ref.watch(vpnStateProvider.select((s) => s.isBusy));
    final caps = ref.watch(vpnCapabilitiesProvider);
    final privilegeAutomation = ref.watch(vpnPrivilegeAutomationStatusProvider);
    final catalog = ref.watch(vpnProtocolCatalogProvider);
    final settingsControlsEnabled = !_reconnecting &&
        !vpnBusy &&
        vpnStatus != VpnStatus.connecting &&
        vpnStatus != VpnStatus.disconnecting;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          children: [
            // ── CONNECTION ───────────────────────────────────────────────
            _SectionLabel(label: 'Connection', isDark: isDark),
            _ToggleCard(
              icon: Icons.bolt_rounded,
              iconColor: AppColors.primary,
              title: 'Auto-connect',
              subtitle: 'Connect automatically when app starts',
              value:
                  ref.watch(preferencesProvider.select((p) => p.autoConnect)),
              onChanged: (v) =>
                  ref.read(preferencesProvider.notifier).setAutoConnect(v),
              enabled: settingsControlsEnabled,
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.space2),
            _PrivilegeAutomationCard(
              isDark: isDark,
              enabled: settingsControlsEnabled,
              requested: ref.watch(preferencesProvider
                  .select((p) => p.privilegeAutomationRequested)),
              statusAsync: privilegeAutomation,
              onToggle: (enabled) =>
                  _handlePrivilegeAutomationToggle(context, enabled),
              onRefresh: () =>
                  ref.invalidate(vpnPrivilegeAutomationStatusProvider),
              onVerify: () => _verifyPrivilegeAutomation(context),
              onRepair: () => _repairPrivilegeAutomation(context),
            ),
            const SizedBox(height: AppSpacing.space2),
            _ToggleCard(
              icon: Icons.shield_rounded,
              iconColor: AppColors.error,
              title: 'Kill Switch',
              subtitle: 'Block all traffic if VPN drops',
              value: ref.watch(preferencesProvider.select((p) => p.killSwitch)),
              onChanged: (v) =>
                  ref.read(preferencesProvider.notifier).setKillSwitch(v),
              enabled: settingsControlsEnabled,
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.space2),
            _ToggleCard(
              icon: Icons.block_rounded,
              iconColor: AppColors.secondary,
              title: 'Ad & Malware Blocking',
              subtitle: 'Block ads and trackers at DNS level',
              value: ref
                  .watch(preferencesProvider.select((p) => p.adBlockEnabled)),
              onChanged: (v) => _handleAdBlockChange(context, v),
              enabled: settingsControlsEnabled,
              isDark: isDark,
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── PROTOCOL ─────────────────────────────────────────────────
            _SectionLabel(label: 'Protocol', isDark: isDark),
            _ProtocolSelector(
              selected: selectedProtocol,
              caps: caps,
              catalog: catalog,
              enabled: settingsControlsEnabled,
              isDark: isDark,
              onSelect: (p) =>
                  ref.read(vpnStateProvider.notifier).selectProtocol(p),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── DIAGNOSTICS ──────────────────────────────────────────────
            _SectionLabel(label: 'Diagnostics', isDark: isDark),
            _DiagnosticsPanel(
              isDark: isDark,
              expanded: _diagExpanded,
              results: _diagResults,
              onToggle: (expanded) {
                setState(() => _diagExpanded = expanded);
                if (expanded && !_diagRunning) unawaited(_runDiagnostics());
              },
              onCopy: () => _copyDiagnostics(context),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── SUPPORT ──────────────────────────────────────────────────
            _SectionLabel(label: 'Support', isDark: isDark),
            _ActionCard(
              icon: Icons.feedback_outlined,
              iconColor: AppColors.primary,
              title: 'Send Feedback',
              subtitle: 'Report bugs or suggest features',
              isDark: isDark,
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => FeedbackSheet(
                  onSubmit: (_, __) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Thanks for your feedback!')),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── DANGER ZONE ──────────────────────────────────────────────
            _SectionLabel(
                label: 'Danger Zone', isDark: isDark, isDestructive: true),
            _DangerCard(
              isDark: isDark,
              onTap: () => _showPanicDialog(context),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── ABOUT ────────────────────────────────────────────────────
            _SectionLabel(label: 'About', isDark: isDark),
            _AboutCard(isDark: isDark),

            const SizedBox(height: AppSpacing.space8),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePrivilegeAutomationToggle(
      BuildContext context, bool enabled) async {
    if (_reconnecting) return;
    final prefs = ref.read(preferencesProvider.notifier);
    final vpnService = ref.read(vpnServiceProvider);
    await prefs.setPrivilegeAutomationRequested(enabled);
    if (!context.mounted) return;
    if (platform.operatingSystem.name.toLowerCase() != 'linux') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Privilege automation setup is currently Linux-only.'),
        ),
      );
      return;
    }
    if (enabled) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Automatic VPN Startup'),
          content: const Text(
            'SecureWave will perform a one-time system setup on Linux so future VPN starts can run without repeated permission prompts. '
            'This installs a scoped helper and policy rule limited to SecureWave WireGuard up/down actions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        await prefs.setPrivilegeAutomationRequested(false);
        return;
      }
    }
    final status = enabled
        ? await vpnService.enablePrivilegeAutomation()
        : await vpnService.disablePrivilegeAutomation();
    if (!context.mounted) return;
    ref.invalidate(vpnPrivilegeAutomationStatusProvider);
    final message = status.message ??
        (enabled
            ? 'Requested privilege automation setup.'
            : 'Requested privilege automation disable.');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _verifyPrivilegeAutomation(BuildContext context) async {
    final vpnService = ref.read(vpnServiceProvider);
    final status = await vpnService.verifyPrivilegeAutomation();
    if (!context.mounted) return;
    ref.invalidate(vpnPrivilegeAutomationStatusProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(status.message ?? 'Verification complete.')),
    );
  }

  Future<void> _repairPrivilegeAutomation(BuildContext context) async {
    final prefs = ref.read(preferencesProvider.notifier);
    await prefs.setPrivilegeAutomationRequested(true);
    if (!context.mounted) return;
    await _handlePrivilegeAutomationToggle(context, true);
  }

  void _handleAdBlockChange(BuildContext context, bool v) {
    if (_reconnecting) return;
    final vpnStatus = ref.read(vpnStateProvider.select((s) => s.status));
    if (vpnStatus == VpnStatus.connected) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reconnect Required'),
          content:
              const Text('This change requires reconnecting. Reconnect now?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reconnect')),
          ],
        ),
      ).then((ok) {
        if (ok == true && mounted && !_reconnecting) {
          ref.read(preferencesProvider.notifier).setAdBlock(v);
          setState(() => _reconnecting = true);
          unawaited(_reconnectAfterSettingChange());
        }
      });
    } else {
      ref.read(preferencesProvider.notifier).setAdBlock(v);
    }
  }

  Future<void> _reconnectAfterSettingChange() async {
    try {
      final notifier = ref.read(vpnStateProvider.notifier);
      await notifier.disconnect();
      if (!mounted) return;
      await notifier.connect();
    } finally {
      if (mounted) {
        setState(() => _reconnecting = false);
      }
    }
  }

  void _showPanicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Panic Mode'),
        content:
            const Text('This will disconnect VPN and sign you out. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(ref.read(vpnStateProvider.notifier).disconnect());
              ref.read(authSessionProvider).clearSession();
              context.go('/login');
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _copyDiagnostics(BuildContext context) {
    final text = _diagResults
            ?.map((r) => '${r.passed ? "PASS" : "FAIL"}: ${r.label}')
            .join('\n') ??
        '';
    Clipboard.setData(ClipboardData(text: 'SecureWave Diagnostics\n$text'));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Diagnostics copied')));
  }

  Future<void> _runDiagnostics() async {
    if (_diagRunning) return;
    setState(() {
      _diagRunning = true;
      _diagResults = [
        _DiagResult('Backend reachable', loading: true),
        _DiagResult('Authentication valid', loading: true),
        _DiagResult('VPN service available', loading: true),
        _DiagResult('Protocol catalog loaded', loading: true),
        _DiagResult('Server list loaded', loading: true),
      ];
    });
    void setDiagResult(int index, _DiagResult result) {
      if (!mounted || _diagResults == null || index >= _diagResults!.length) {
        return;
      }
      setState(() => _diagResults![index] = result);
    }

    final api = ref.read(apiClientProvider);
    final vpnService = ref.read(vpnServiceProvider);
    final authSession = ref.read(authSessionProvider);
    final appConfig = ref.read(appConfigProvider);

    try {
      try {
        final health = await api.fetchHealth();
        final service = health['service']?.toString();
        final status = health['status']?.toString();
        final detail = [
          if (service != null && service.isNotEmpty) service,
          if (status != null && status.isNotEmpty) 'status=$status',
          appConfig.apiBaseUrl,
        ].join(' • ');
        setDiagResult(
            0, _DiagResult('Backend reachable', passed: true, detail: detail));
      } catch (error) {
        setDiagResult(
          0,
          _DiagResult(
            'Backend reachable',
            passed: false,
            detail: ApiError.messageFrom(error),
          ),
        );
      }

      if (!mounted) return;
      if (!authSession.isAuthenticated) {
        setDiagResult(
          1,
          _DiagResult(
            'Authentication valid',
            passed: false,
            detail: 'Not signed in',
          ),
        );
      } else {
        try {
          final plan = await api.fetchUserPlan(forceRefresh: true);
          setDiagResult(
            1,
            _DiagResult(
              'Authentication valid',
              passed: true,
              detail: 'Signed in • plan=${plan.name}',
            ),
          );
        } catch (error) {
          setDiagResult(
            1,
            _DiagResult(
              'Authentication valid',
              passed: false,
              detail: ApiError.messageFrom(error),
            ),
          );
        }
      }

      if (!mounted) return;
      try {
        final capabilities = await vpnService.getCapabilities();
        final nativeReady = capabilities.wireGuard ||
            capabilities.openVpn ||
            capabilities.ikev2;
        final availableProtocols = <String>[
          if (capabilities.wireGuard) vpnProtocolLabel(VpnProtocol.wireGuard),
          if (capabilities.openVpn) vpnProtocolLabel(VpnProtocol.openVpn),
          if (capabilities.ikev2) vpnProtocolLabel(VpnProtocol.ikev2),
        ];
        final detail = nativeReady
            ? 'Native runtimes: ${availableProtocols.join(", ")}'
            : (capabilities.wireGuardInstallHint ??
                capabilities.openVpnInstallHint ??
                capabilities.ikev2InstallHint ??
                vpnService.availabilityMessage ??
                'No native VPN runtime detected');
        setDiagResult(
          2,
          _DiagResult('VPN service available',
              passed: nativeReady, detail: detail),
        );
      } catch (error) {
        setDiagResult(
          2,
          _DiagResult(
            'VPN service available',
            passed: false,
            detail: error.toString(),
          ),
        );
      }

      if (!mounted) return;
      try {
        final protocolCatalog = await api.fetchVpnProtocols(
          deviceType: ProtocolCapabilityMatrix.currentDeviceType(),
        );
        final enabled = protocolCatalog.enabledProtocols().toList()
          ..sort((a, b) => vpnProtocolLabel(a).compareTo(vpnProtocolLabel(b)));
        setDiagResult(
          3,
          _DiagResult(
            'Protocol catalog loaded',
            passed: true,
            detail: enabled.isEmpty
                ? 'No protocols enabled for current plan/device'
                : 'Enabled: ${enabled.map(vpnProtocolLabel).join(", ")}',
          ),
        );
      } catch (error) {
        setDiagResult(
          3,
          _DiagResult(
            'Protocol catalog loaded',
            passed: false,
            detail: ApiError.messageFrom(error),
          ),
        );
      }

      if (!mounted) return;
      try {
        final servers = await api.fetchServers(forceRefresh: true);
        setDiagResult(
          4,
          _DiagResult(
            'Server list loaded',
            passed: servers.isNotEmpty,
            detail: servers.isEmpty
                ? 'No servers returned'
                : '${servers.length} servers',
          ),
        );
      } catch (error) {
        setDiagResult(
          4,
          _DiagResult(
            'Server list loaded',
            passed: false,
            detail: ApiError.messageFrom(error),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _diagRunning = false);
      }
    }
  }
}

class _PrivilegeAutomationCard extends StatelessWidget {
  const _PrivilegeAutomationCard({
    required this.isDark,
    required this.enabled,
    required this.requested,
    required this.statusAsync,
    required this.onToggle,
    required this.onRefresh,
    required this.onVerify,
    required this.onRepair,
  });

  final bool isDark;
  final bool enabled;
  final bool requested;
  final AsyncValue<VpnPrivilegeAutomationStatus> statusAsync;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onVerify;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    final status = statusAsync.valueOrNull;
    final os = platform.operatingSystem.name.toLowerCase();
    final supported = os == 'linux' && (status?.supported ?? false);
    final subtitle = statusAsync.when(
      data: (s) {
        if (os != 'linux') {
          return 'One-time no-prompt setup is currently available on Linux only';
        }
        if (!s.supported) {
          return s.message ??
              'Linux privilege automation setup not available yet';
        }
        if (s.enabled) return 'Enabled (${s.backend})';
        if (s.needsSetup) {
          if (!s.pkexecAvailable) {
            return 'Needs PolicyKit (pkexec) installed before setup can run';
          }
          if (!s.desktopAuthSession) {
            return 'Needs desktop polkit auth session/agent running for one-time setup';
          }
          if (s.helperInstalled != s.ruleInstalled) {
            return 'Setup is partially installed. Re-run setup to repair it';
          }
          return s.message ?? 'Needs one-time setup';
        }
        return s.message ?? 'Disabled';
      },
      loading: () => 'Checking setup status…',
      error: (e, _) => 'Status check failed: $e',
    );

    return Card(
      elevation: 0,
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined,
                    color: AppColors.primary),
                const SizedBox(width: AppSpacing.space2),
                const Expanded(
                  child: Text(
                    'Automatic VPN Startup (no prompts)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Switch(
                  value: requested,
                  onChanged: enabled ? onToggle : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.inkMuted,
                height: 1.25,
              ),
            ),
            if (os == 'linux') ...[
              const SizedBox(height: AppSpacing.space2),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled ? onRefresh : null,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh status'),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  OutlinedButton.icon(
                    onPressed: enabled ? onVerify : null,
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Verify'),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  OutlinedButton.icon(
                    onPressed: enabled ? onRepair : null,
                    icon: const Icon(Icons.build_outlined, size: 16),
                    label: const Text('Repair setup'),
                  ),
                ],
              ),
              if (supported && status != null) ...[
                const SizedBox(height: AppSpacing.space1),
                Text(
                  _linuxPrivilegeAutomationDetails(status),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _linuxPrivilegeAutomationDetails(VpnPrivilegeAutomationStatus status) {
    final checks = <String>[
      'pkexec: ${status.pkexecAvailable ? "yes" : "no"}',
      'auth agent: ${status.desktopAuthSession ? "yes" : "no"}',
      'helper: ${status.helperInstalled ? "yes" : "no"}',
      'rule: ${status.ruleInstalled ? "yes" : "no"}',
    ];
    return checks.join(' • ');
  }
}

// ── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.isDark,
    this.isDestructive = false,
  });

  final String label;
  final bool isDark;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.space2,
        bottom: AppSpacing.space2,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: AppSpacing.space2),
            decoration: BoxDecoration(
              color: isDestructive ? AppColors.error : AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDestructive ? AppColors.error : null,
                  letterSpacing: 0.8,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle card ────────────────────────────────────────────────────────────

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.isDark,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 0.5,
          ),
        ),
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            ),
            child: Icon(icon, size: AppSpacing.iconS, color: iconColor),
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          subtitle:
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          trailing: Switch(value: value, onChanged: enabled ? onChanged : null),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
          ),
        ),
      ),
    );
  }
}

// ── Protocol selector ──────────────────────────────────────────────────────

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({
    required this.selected,
    required this.caps,
    required this.catalog,
    required this.enabled,
    required this.isDark,
    required this.onSelect,
  });

  final VpnProtocol selected;
  final AsyncValue<VpnCapabilities> caps;
  final AsyncValue<VpnProtocolCatalog> catalog;
  final bool enabled;
  final bool isDark;
  final void Function(VpnProtocol) onSelect;

  String? _protocolSubtitle(BuildContext context, VpnProtocol protocol) {
    final platform = Theme.of(context).platform;
    if (protocol == VpnProtocol.auto) {
      return 'Automatically chooses the first live protocol runtime.';
    }
    return switch (platform) {
      TargetPlatform.linux => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Native WireGuard runtime (elevation required; no prompt if helper automation is installed).',
          VpnProtocol.openVpn =>
            'Requires local OpenVPN client, elevation, and backend OpenVPN profile.',
          VpnProtocol.ikev2 =>
            'Requires OS helper (NetworkManager/strongSwan).',
          VpnProtocol.auto => null,
        },
      TargetPlatform.windows => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Uses installed WireGuard for Windows runtime.',
          VpnProtocol.openVpn =>
            'Uses OpenVPN for Windows (UAC prompt may appear).',
          VpnProtocol.ikev2 => 'Uses built-in Windows VPN (RAS/VPN API path).',
          VpnProtocol.auto => null,
        },
      TargetPlatform.macOS => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Shown only when this build includes signed Network Extension support.',
          VpnProtocol.openVpn =>
            'Requires signed Packet Tunnel / Network Extension support.',
          VpnProtocol.ikev2 =>
            'Requires NEVPNManager entitlements and signing.',
          VpnProtocol.auto => null,
        },
      _ => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Uses the native VPN runtime on this device.',
          VpnProtocol.openVpn =>
            'Uses the native OpenVPN runtime on this device.',
          VpnProtocol.ikev2 => 'Uses OS-provided IKEv2/IPsec support.',
          VpnProtocol.auto => null,
        },
    };
  }

  String? _backendUnavailableReason(
    VpnProtocol protocol,
    VpnProtocolCatalog? catalog,
  ) {
    VpnProtocolCatalogEntry? entry;
    if (catalog != null) {
      for (final item in catalog.protocols) {
        if (item.protocol == protocol) {
          entry = item;
          break;
        }
      }
    }
    final reason = entry?.reason;
    return switch (reason) {
      'disabled_server_side' =>
        '${vpnProtocolLabel(protocol)} is disabled by backend policy.',
      'restricted_by_plan' =>
        '${vpnProtocolLabel(protocol)} is not available on your plan.',
      'not_supported_on_platform' =>
        '${vpnProtocolLabel(protocol)} is not supported on this platform.',
      'no_active_server_support' =>
        'No active SecureWave servers currently advertise ${vpnProtocolLabel(protocol)}.',
      'server_material_incomplete' =>
        '${vpnProtocolLabel(protocol)} is enabled in backend flags but server config material is incomplete.',
      'protocol_healthcheck_fail' =>
        '${vpnProtocolLabel(protocol)} is temporarily disabled because server healthchecks are failing.',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 480 ? 2 : 1;
        final capsData = caps.valueOrNull;
        final catalogData = catalog.valueOrNull;
        final loadingCapabilities = capsData == null || catalogData == null;
        final availability = loadingCapabilities
            ? const <VpnProtocolAvailability>[]
            : ProtocolCapabilityMatrix.evaluate(
                nativeCapabilities: capsData,
                backendEnabledProtocols: catalogData.enabledProtocols(),
              );
        final availabilityByProtocol = <VpnProtocol, VpnProtocolAvailability>{
          for (final item in availability) item.protocol: item,
        };
        final anyConcreteAvailable = availability.any((item) => item.available);
        final selectable = <VpnProtocol>[
          VpnProtocol.auto,
          ...ProtocolCapabilityMatrix.orderedProtocols(),
        ];
        final statusTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (caps.isLoading || catalog.isLoading)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: Text(
                  'Checking backend protocol flags and native VPN runtime support...',
                  style: statusTextStyle,
                ),
              ),
            if ((caps.hasError || catalog.hasError) &&
                !(caps.isLoading || catalog.isLoading))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: Text(
                  'Protocol availability could not be fully loaded. You can still choose Auto.',
                  style: statusTextStyle?.copyWith(color: AppColors.error),
                ),
              ),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: selectable.map((p) {
                final isSelected = selected == p;
                final availabilityItem = availabilityByProtocol[p];
                final isLoadingOption =
                    p != VpnProtocol.auto && loadingCapabilities;
                final isSelectable = enabled &&
                    (p == VpnProtocol.auto ||
                        (availabilityItem?.available ?? false));
                final subtitle = _protocolSubtitle(context, p);
                final statusLine = !enabled
                    ? 'Please wait for the current VPN action to finish.'
                    : isLoadingOption
                        ? 'Checking backend + device support...'
                        : (availabilityItem?.backendEnabled == false
                            ? (_backendUnavailableReason(p, catalogData) ??
                                availabilityItem?.unavailableReason)
                            : availabilityItem?.unavailableReason);
                final semanticHint = isSelectable
                    ? (subtitle == null
                        ? 'Double tap to select ${vpnProtocolLabel(p)}.'
                        : '$subtitle Double tap to select.')
                    : (statusLine ?? 'This option is unavailable right now.');

                return SizedBox(
                  width: cols == 2
                      ? (constraints.maxWidth - AppSpacing.space2) / 2
                      : double.infinity,
                  child: Opacity(
                    opacity: isSelectable ? 1 : 0.62,
                    child: Semantics(
                      button: true,
                      enabled: isSelectable,
                      selected: isSelected,
                      label: 'VPN protocol ${vpnProtocolLabel(p)}',
                      hint: semanticHint,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusXL),
                          onTap: isSelectable ? () => onSelect(p) : null,
                          child: AnimatedContainer(
                            duration: AppAnimations.durationFast,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space4,
                              vertical: AppSpacing.space3,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                      ? AppColors.primaryBright
                                          .withValues(alpha: 0.12)
                                      : AppColors.primaryLight)
                                  : (isDark
                                      ? AppColors.darkSurface
                                      : AppColors.surface),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusXL),
                              border: Border.all(
                                color: isSelected
                                    ? (isDark
                                        ? AppColors.primaryBright
                                        : AppColors.primary)
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.border),
                                width: isSelected ? 1.5 : 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: AppAnimations.durationFast,
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? (isDark
                                            ? AppColors.primaryBright
                                            : AppColors.primary)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? (isDark
                                              ? AppColors.primaryBright
                                              : AppColors.primary)
                                          : (isDark
                                              ? AppColors.darkInkSoft
                                              : AppColors.inkSoft),
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 10,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: AppSpacing.space3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        vpnProtocolLabel(p),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                      if (subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: isDark
                                                    ? AppColors.darkInkSoft
                                                    : AppColors.inkMuted,
                                                height: 1.2,
                                              ),
                                        ),
                                      ],
                                      if (statusLine != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          statusLine,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: !enabled
                                                    ? (isDark
                                                        ? AppColors.darkInkSoft
                                                        : AppColors.inkMuted)
                                                    : AppColors.error,
                                                height: 1.2,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (!loadingCapabilities && !anyConcreteAvailable)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.space2),
                child: Text(
                  'No concrete VPN protocol is currently available on this device. Auto will retry after prerequisites are installed or backend flags change.',
                  style: statusTextStyle?.copyWith(color: AppColors.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Diagnostics panel ──────────────────────────────────────────────────────

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.isDark,
    required this.expanded,
    required this.results,
    required this.onToggle,
    required this.onCopy,
  });

  final bool isDark;
  final bool expanded;
  final List<_DiagResult>? results;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            ),
            child: const Icon(Icons.health_and_safety_outlined,
                size: AppSpacing.iconS, color: AppColors.primary),
          ),
          title: Text(
            'Run Diagnostics',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          initiallyExpanded: expanded,
          onExpansionChanged: onToggle,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          ),
          children: [
            if (results != null)
              ...results!.map((r) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space5),
                    leading: r.loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            r.passed
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color:
                                r.passed ? AppColors.success : AppColors.error,
                            size: 20),
                    title: Text(r.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            )),
                    subtitle: r.detail != null
                        ? Text(r.detail!,
                            style: Theme.of(context).textTheme.bodySmall)
                        : null,
                  )),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space3),
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copy Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action card ────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: Icon(icon, size: AppSpacing.iconS, color: iconColor),
        ),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Icon(Icons.chevron_right_rounded,
            size: AppSpacing.iconS,
            color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── Danger card ────────────────────────────────────────────────────────────

class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.isDark, required this.onTap});
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.25),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              size: AppSpacing.iconS, color: AppColors.error),
        ),
        title: Text(
          'Panic Mode',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: const Text('Emergency disconnect and clear all data'),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── About card ─────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('Version'),
            subtitle: const Text('SecureWave v4.0.0'),
            leading: Icon(Icons.info_outline_rounded,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? AppColors.darkBorder : AppColors.border),
          ListTile(
            title: const Text('Privacy Policy'),
            leading: Icon(Icons.privacy_tip_outlined,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            trailing: Icon(Icons.open_in_new_rounded,
                size: 14,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            onTap: () {},
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? AppColors.darkBorder : AppColors.border),
          ListTile(
            title: const Text('Terms of Service'),
            leading: Icon(Icons.gavel_rounded,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            trailing: Icon(Icons.open_in_new_rounded,
                size: 14,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ── Data classes ───────────────────────────────────────────────────────────

class _DiagResult {
  _DiagResult(this.label,
      {this.passed = false, this.loading = false, this.detail});
  final String label;
  final bool passed;
  final bool loading;
  final String? detail;
}
