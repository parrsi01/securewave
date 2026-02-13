import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import 'widgets/diagnostics_dialog.dart';
import '../../features/onboarding/feedback_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _autoConnect = false;
  bool _killSwitch = false;

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space4,
            ),
            children: [
              // ── Connection ──────────────────────────────────────────────
              _SectionHeader(title: 'Connection'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto-connect on startup'),
                      subtitle: const Text(
                        'Automatically establish a VPN connection when the app launches.',
                      ),
                      value: _autoConnect,
                      onChanged: (value) => setState(() => _autoConnect = value),
                      activeColor: AppColors.primary,
                    ),
                    const Divider(height: 1, indent: AppSpacing.space4),
                    SwitchListTile(
                      title: const Text('Kill switch'),
                      subtitle: const Text(
                        'Block all internet traffic if the VPN connection drops unexpectedly.',
                      ),
                      value: _killSwitch,
                      onChanged: (value) => setState(() => _killSwitch = value),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space5),

              // ── Protocol ────────────────────────────────────────────────
              _SectionHeader(title: 'Protocol'),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select the tunneling protocol used for VPN connections.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<VpnProtocol>(
                          segments: [
                            ButtonSegment<VpnProtocol>(
                              value: VpnProtocol.wireGuard,
                              label: const Text('WireGuard'),
                              icon: const Icon(Icons.lock, size: 16),
                            ),
                            ButtonSegment<VpnProtocol>(
                              value: VpnProtocol.ikev2,
                              label: const Text('IKEv2'),
                              enabled: false,
                            ),
                            ButtonSegment<VpnProtocol>(
                              value: VpnProtocol.openVpn,
                              label: const Text('OpenVPN'),
                              enabled: false,
                            ),
                          ],
                          selected: {vpnState.protocol},
                          onSelectionChanged: (selected) {
                            ref
                                .read(vpnStateProvider.notifier)
                                .selectProtocol(selected.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.space5),

              // ── Diagnostics ─────────────────────────────────────────────
              _SectionHeader(title: 'Diagnostics'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Run Diagnostics'),
                  subtitle: const Text(
                    'Check backend, auth, and VPN service health.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDiagnosticsDialog(context),
                ),
              ),

              const SizedBox(height: AppSpacing.space5),

              // ── Feedback ──────────────────────────────────────────────
              _SectionHeader(title: 'Feedback'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('Send Feedback'),
                  subtitle: const Text(
                    'Report bugs, request features, or share your thoughts.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showFeedbackSheet(context),
                ),
              ),

              const SizedBox(height: AppSpacing.space5),

              // ── Danger Zone ─────────────────────────────────────────────
              _SectionHeader(title: 'Danger Zone'),
              Card(
                margin: EdgeInsets.zero,
                color: AppColors.error.withValues(alpha: 0.05),
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  title: Text(
                    'Panic Mode',
                    style: TextStyle(color: AppColors.error),
                  ),
                  subtitle: const Text(
                    'Immediately disconnect VPN, clear session, and sign out.',
                  ),
                  trailing: Icon(Icons.chevron_right, color: AppColors.error),
                  onTap: () => _confirmPanicMode(context),
                ),
              ),

              const SizedBox(height: AppSpacing.space5),

              // ── About ───────────────────────────────────────────────────
              _SectionHeader(title: 'About'),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('App Version'),
                      trailing: Text(
                        '1.0.0',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: AppSpacing.space4),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Privacy Policy will open in browser.')),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: AppSpacing.space4),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Terms of Service'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terms of Service will open in browser.')),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space6),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeedbackSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FeedbackSheet(
        onSubmit: (category, description) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thank you for your feedback!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _showDiagnosticsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const DiagnosticsDialog(),
    );
  }

  Future<void> _confirmPanicMode(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activate Panic Mode?'),
        content: const Text(
          'This will immediately disconnect the VPN, clear your session data, '
          'and sign you out. You will need to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Disconnect VPN
      await ref.read(vpnStateProvider.notifier).disconnect();
      // Clear auth session (triggers logout)
      await ref.read(authSessionProvider).clearSession();
      // Navigate to login
      if (mounted) {
        GoRouter.of(context).go('/login');
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.space1,
        bottom: AppSpacing.space2,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
