import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/vpn_protocol.dart';
import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Status display — v2.
///
/// Large animated status text with connection timer.
/// Uses AnimatedSwitcher for smooth state transitions.
class StatusDisplay extends ConsumerStatefulWidget {
  const StatusDisplay({super.key});

  @override
  ConsumerState<StatusDisplay> createState() => _StatusDisplayState();
}

class _StatusDisplayState extends ConsumerState<StatusDisplay> {
  Timer? _timer;
  DateTime? _connectedSince;
  Duration _elapsed = Duration.zero;

  void _syncTimer(VpnStatus status) {
    if (status == VpnStatus.connected) {
      _connectedSince ??= DateTime.now();
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _connectedSince != null) {
          setState(
              () => _elapsed = DateTime.now().difference(_connectedSince!));
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _connectedSince = null;
      _elapsed = Duration.zero;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _setupHelpMessage({
    required TargetPlatform platform,
    required VpnProtocol protocol,
    required VpnErrorKind? kind,
  }) {
    if (kind == VpnErrorKind.permissionRequired) {
      return switch (platform) {
        TargetPlatform.linux => 'Administrator permission is required.\n'
            'Approve the pkexec prompt and ensure a PolicyKit agent is running.',
        TargetPlatform.windows => 'Administrator permission is required.\n'
            'Approve the UAC prompt for tunnel setup.',
        TargetPlatform.macOS =>
          'This build cannot request VPN privileges on macOS.\n'
              'A signed Network Extension build is required.',
        _ => 'Approve the system permission prompt and retry.',
      };
    }
    if (protocol == VpnProtocol.openVpn) {
      return switch (platform) {
        TargetPlatform.linux =>
          'OpenVPN requires a local OpenVPN client runtime.\n'
              'Install: sudo apt-get install openvpn',
        TargetPlatform.windows => 'OpenVPN requires OpenVPN for Windows.\n'
            'Install OpenVPN and retry the connection.',
        TargetPlatform.macOS =>
          'OpenVPN is not available in this macOS build.\n'
              'A signed Packet Tunnel/Network Extension target is required.',
        _ => 'OpenVPN runtime is unavailable on this device.',
      };
    }
    if (protocol == VpnProtocol.ikev2) {
      return switch (platform) {
        TargetPlatform.linux => 'IKEv2 requires system components on Linux.\n'
            'Install NetworkManager + network-manager-strongswan + strongSwan.',
        TargetPlatform.windows =>
          'Windows IKEv2 automation currently expects EAP-MSCHAPv2 credentials.\n'
              'If your profile is EAP-TLS, switch backend auth mode or provision manually.',
        TargetPlatform.macOS => 'IKEv2 is not available in this macOS build.\n'
            'NEVPNManager entitlements and signing are required.',
        _ => 'IKEv2/IPsec runtime is unavailable on this device.',
      };
    }
    return 'Review protocol requirements and runtime setup, then retry.';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vpnStateProvider.select((s) => s.status));
    final statusText = ref.watch(
        vpnStateProvider.select((s) => s.statusText(includeEllipsis: true)));
    final statusColor =
        ref.watch(vpnStateProvider.select((s) => s.statusColor));
    final selectedProtocol =
        ref.watch(vpnStateProvider.select((s) => s.protocol));
    final effectiveProtocol =
        ref.watch(vpnStateProvider.select((s) => s.effectiveProtocol));
    final errorKind = ref.watch(vpnStateProvider.select((s) => s.errorKind));
    final errorMessage = ref.watch(
      vpnStateProvider.select(
        (s) => s.status == VpnStatus.error ? s.errorMessage : null,
      ),
    );
    _syncTimer(status);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Status label ────────────────────────────────────────────────
        AnimatedSwitcher(
          duration: AppAnimations.durationNormal,
          switchInCurve: AppAnimations.curveEnter,
          switchOutCurve: AppAnimations.curveExit,
          child: Text(
            statusText,
            key: ValueKey(status),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
            textAlign: TextAlign.center,
          ),
        ),

        // ── Connection timer ─────────────────────────────────────────────
        AnimatedSize(
          duration: AppAnimations.durationNormal,
          curve: AppAnimations.curveDefault,
          child: status == VpnStatus.connected
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space1),
                  child: Text(
                    _fmt(_elapsed),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.success.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Error message ────────────────────────────────────────────────
        if (status == VpnStatus.error && errorMessage != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusL),
            ),
            child: Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => unawaited(
                  ref.read(vpnStateProvider.notifier).connect(),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final protocol = effectiveProtocol ??
                      (selectedProtocol == VpnProtocol.auto
                          ? VpnProtocol.wireGuard
                          : selectedProtocol);
                  final platform = Theme.of(context).platform;
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Setup help'),
                      content: Text(
                        _setupHelpMessage(
                          platform: platform,
                          protocol: protocol,
                          kind: errorKind,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            context.go('/settings');
                          },
                          child: const Text('Open Settings'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Setup help'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
