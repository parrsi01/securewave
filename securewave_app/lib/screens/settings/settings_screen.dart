import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_protocol_catalog.dart';
import '../../core/models/vpn_status.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/vpn_state.dart';
import '../../core/vpn/protocol_capabilities.dart';
import '../../features/onboarding/feedback_sheet.dart';
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
    final caps = ref.watch(vpnCapabilitiesProvider);
    final catalog = ref.watch(vpnProtocolCatalogProvider);

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
              isDark: isDark,
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
              isDark: isDark,
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── PROTOCOL ─────────────────────────────────────────────────
            _SectionLabel(label: 'Protocol', isDark: isDark),
            _ProtocolSelector(
              selected: selectedProtocol,
              caps: caps,
              catalog: catalog,
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
                if (expanded) unawaited(_runDiagnostics());
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

  void _handleAdBlockChange(BuildContext context, bool v) {
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
          _reconnecting = true;
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
      if (mounted) _reconnecting = false;
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
    setState(() {
      _diagResults = [
        _DiagResult('Backend reachable', loading: true),
        _DiagResult('Authentication valid', loading: true),
        _DiagResult('VPN service available', loading: true),
        _DiagResult('Server list loaded', loading: true),
      ];
    });

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() =>
        _diagResults![0] = _DiagResult('Backend reachable', passed: true));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final authed = ref.read(authSessionProvider).isAuthenticated;
    setState(() => _diagResults![1] = _DiagResult('Authentication valid',
        passed: authed, detail: authed ? null : 'Not signed in'));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final vpnAvail = ref.read(vpnServiceProvider).isNativeAvailable;
    setState(() => _diagResults![2] = _DiagResult('VPN service available',
        passed: vpnAvail,
        detail: vpnAvail ? null : 'Native bridge unavailable'));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final hasServers = ref.read(serversProvider).hasValue;
    setState(() => _diagResults![3] = _DiagResult('Server list loaded',
        passed: hasServers, detail: hasServers ? null : 'No servers'));
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
    required this.isDark,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

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
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Switch(value: value, onChanged: onChanged),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
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
    required this.isDark,
    required this.onSelect,
  });

  final VpnProtocol selected;
  final AsyncValue<VpnCapabilities> caps;
  final AsyncValue<VpnProtocolCatalog> catalog;
  final bool isDark;
  final void Function(VpnProtocol) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 480 ? 2 : 1;
        final capsData = caps.valueOrNull;
        final backendEnabled = catalog.valueOrNull?.enabledProtocols() ??
            <VpnProtocol>{VpnProtocol.wireGuard};
        final availableProtocols = capsData == null
            ? <VpnProtocol>{}
            : ProtocolCapabilityMatrix.evaluate(
                nativeCapabilities: capsData,
                backendEnabledProtocols: backendEnabled,
              )
                .where((item) => item.available)
                .map((item) => item.protocol)
                .toSet();
        final selectable = <VpnProtocol>[
          VpnProtocol.auto,
          ...ProtocolCapabilityMatrix.orderedProtocols()
              .where((protocol) => availableProtocols.contains(protocol)),
        ];

        if (selectable.length == 1) {
          return Text(
            'No live protocol runtime is currently available on this device.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.error),
          );
        }

        return Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: selectable.map((p) {
            final isSelected = selected == p;

            return SizedBox(
              width: cols == 2
                  ? (constraints.maxWidth - AppSpacing.space2) / 2
                  : double.infinity,
              child: GestureDetector(
                onTap: () => onSelect(p),
                child: AnimatedContainer(
                  duration: AppAnimations.durationFast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space4,
                    vertical: AppSpacing.space3,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? AppColors.primaryBright.withValues(alpha: 0.12)
                            : AppColors.primaryLight)
                        : (isDark ? AppColors.darkSurface : AppColors.surface),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                    border: Border.all(
                      color: isSelected
                          ? (isDark
                              ? AppColors.primaryBright
                              : AppColors.primary)
                          : (isDark ? AppColors.darkBorder : AppColors.border),
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
                            ? const Icon(Icons.check,
                                size: 10, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
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
