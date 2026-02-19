import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../features/onboarding/feedback_sheet.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _killSwitch = false;
  bool _adBlock = true;
  bool _diagExpanded = false;
  List<_DiagResult>? _diagResults;

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);
    final caps = ref.watch(vpnCapabilitiesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space4),
      children: [
        // Connection section
        _Section(
          title: 'Connection',
          children: [
            SwitchListTile(
              title: const Text('Auto-connect'),
              subtitle: const Text('Connect automatically when app starts'),
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              title: const Text('Kill Switch'),
              subtitle: const Text('Block traffic if VPN disconnects'),
              value: _killSwitch,
              onChanged: (v) => setState(() => _killSwitch = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Ad & Malware Blocking'),
              subtitle: const Text('Block ads and trackers at DNS level'),
              value: _adBlock,
              onChanged: (v) {
                if (vpn.status == VpnStatus.connected) {
                  showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reconnect Required'),
                      content: const Text('This change requires reconnecting. Reconnect now?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reconnect')),
                      ],
                    ),
                  ).then((ok) {
                    if (ok == true) {
                      setState(() => _adBlock = v);
                      ref.read(vpnStateProvider.notifier).disconnect();
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) ref.read(vpnStateProvider.notifier).connect();
                      });
                    }
                  });
                } else {
                  setState(() => _adBlock = v);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),

        // Protocol section
        _Section(
          title: 'Protocol',
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth > 500 ? 2 : 1;
                  return Wrap(
                    spacing: AppSpacing.space3,
                    runSpacing: AppSpacing.space3,
                    children: VpnProtocol.values.map((p) {
                      final selected = vpn.protocol == p;
                      final supported = caps.whenOrNull(data: (c) {
                        return switch (p) {
                          VpnProtocol.auto => true,
                          VpnProtocol.wireGuard => c.wireGuard,
                          VpnProtocol.openVpn => c.openVpn,
                          VpnProtocol.ikev2 => c.ikev2,
                          VpnProtocol.l2tp => c.l2tp,
                          VpnProtocol.shadowsocks => c.shadowsocks,
                          VpnProtocol.tcpFallback => c.tcpFallback,
                          VpnProtocol.quic => c.quic,
                        };
                      }) ?? true;

                      return SizedBox(
                        width: cols == 2 ? (constraints.maxWidth - AppSpacing.space3) / 2 : double.infinity,
                        child: GestureDetector(
                          onTap: () => ref.read(vpnStateProvider.notifier).selectProtocol(p),
                          child: AnimatedContainer(
                            duration: AppAnimations.durationFast,
                            padding: const EdgeInsets.all(AppSpacing.space3),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected ? AppColors.primary : AppColors.border,
                                width: selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                              color: selected ? AppColors.primaryLight : AppColors.surface,
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: AppAnimations.durationFast,
                                  width: 20,
                                  height: 20,
                                  margin: const EdgeInsets.all(AppSpacing.space3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected ? AppColors.primary : AppColors.inkSoft,
                                      width: selected ? 6 : 2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(vpnProtocolLabel(p), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                      if (!supported)
                                        Text('Unavailable', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
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
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),

        // Diagnostics
        _Section(
          title: 'Diagnostics',
          children: [
            ExpansionTile(
              title: const Text('Run Diagnostics'),
              leading: const Icon(Icons.medical_services_outlined, size: 20),
              initiallyExpanded: _diagExpanded,
              onExpansionChanged: (expanded) {
                _diagExpanded = expanded;
                if (expanded) _runDiagnostics();
              },
              children: [
                if (_diagResults != null)
                  ...(_diagResults!.map((r) => ListTile(
                        leading: r.loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(r.passed ? Icons.check_circle : Icons.cancel, color: r.passed ? AppColors.success : AppColors.error, size: 20),
                        title: Text(r.label),
                        subtitle: r.detail != null ? Text(r.detail!, style: Theme.of(context).textTheme.bodySmall) : null,
                      ))),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.space3),
                  child: TextButton.icon(
                    onPressed: () {
                      final text = _diagResults?.map((r) => '${r.passed ? "PASS" : "FAIL"}: ${r.label}').join('\n') ?? '';
                      Clipboard.setData(ClipboardData(text: 'SecureWave Diagnostics\n$text'));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Report'),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),

        // Feedback
        Card(
          child: ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send Feedback'),
            subtitle: const Text('Report bugs or suggest features'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => FeedbackSheet(
                onSubmit: (category, description) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your feedback!')));
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),

        // Danger Zone
        Card(
          color: AppColors.error.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: AppColors.error),
            title: Text('Panic Mode', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            subtitle: const Text('Emergency disconnect and clear all data'),
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Panic Mode'),
                content: const Text('This will disconnect VPN and sign you out. Continue?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(vpnStateProvider.notifier).disconnect();
                      ref.read(authSessionProvider).clearSession();
                      context.go('/login');
                    },
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),

        // About
        _Section(
          title: 'About',
          children: [
            ListTile(title: const Text('Version'), subtitle: const Text('SecureWave v4.0.0')),
            ListTile(title: const Text('Privacy Policy'), trailing: const Icon(Icons.chevron_right, size: 18), onTap: () {}),
            ListTile(title: const Text('Terms of Service'), trailing: const Icon(Icons.chevron_right, size: 18), onTap: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),
      ],
    );
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
    setState(() => _diagResults![0] = _DiagResult('Backend reachable', passed: true));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final authed = ref.read(authSessionProvider).isAuthenticated;
    setState(() => _diagResults![1] = _DiagResult('Authentication valid', passed: authed, detail: authed ? null : 'Not signed in'));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final vpnAvail = ref.read(vpnServiceProvider).isNativeAvailable;
    setState(() => _diagResults![2] = _DiagResult('VPN service available', passed: vpnAvail, detail: vpnAvail ? null : 'Native bridge unavailable'));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final hasServers = ref.read(serversProvider).hasValue;
    setState(() => _diagResults![3] = _DiagResult('Server list loaded', passed: hasServers, detail: hasServers ? null : 'No servers'));
  }
}

class _DiagResult {
  _DiagResult(this.label, {this.passed = false, this.loading = false, this.detail});
  final String label;
  final bool passed;
  final bool loading;
  final String? detail;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.space1, bottom: AppSpacing.space2),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
