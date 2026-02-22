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
  Duration? _timerCadence;
  DateTime? _connectedSince;
  Duration _elapsed = Duration.zero;
  DateTime _tickNow = DateTime.now();

  void _syncTimer(VpnStatus status) {
    final isConnected = status == VpnStatus.connected;
    final isConnecting = status == VpnStatus.connecting;
    final shouldTick = isConnected || isConnecting;
    final cadence =
        isConnected ? const Duration(seconds: 1) : const Duration(seconds: 2);
    if (shouldTick) {
      if (isConnected) {
        _connectedSince ??= DateTime.now();
      } else {
        _connectedSince = null;
        _elapsed = Duration.zero;
      }
      if (_timer != null && _timerCadence != cadence) {
        _timer?.cancel();
        _timer = null;
      }
      _timerCadence = cadence;
      _timer ??= Timer.periodic(cadence, (_) {
        if (!mounted) return;
        setState(() {
          _tickNow = DateTime.now();
          if (_connectedSince != null) {
            _elapsed = _tickNow.difference(_connectedSince!);
          }
        });
      });
      _tickNow = DateTime.now();
    } else {
      _timer?.cancel();
      _timer = null;
      _timerCadence = null;
      _connectedSince = null;
      _elapsed = Duration.zero;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerCadence = null;
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

  String? _activeProtocolLabel({
    required VpnProtocol selected,
    required VpnProtocol? effective,
  }) {
    if (selected == VpnProtocol.auto && effective == null) {
      return null;
    }
    if (selected == VpnProtocol.auto && effective != null) {
      return 'Automatic -> ${vpnProtocolLabel(effective)}';
    }
    if (effective != null && effective != selected) {
      return '${vpnProtocolLabel(selected)} -> ${vpnProtocolLabel(effective)}';
    }
    return vpnProtocolLabel(effective ?? selected);
  }

  String? _platformHelperHint(TargetPlatform platform, VpnProtocol protocol) {
    if (protocol == VpnProtocol.wireGuard) {
      return switch (platform) {
        TargetPlatform.linux => 'Native runtime + admin prompt',
        TargetPlatform.windows => 'WireGuard for Windows runtime',
        TargetPlatform.macOS => 'Signed NE build required',
        _ => 'Native runtime',
      };
    }
    if (protocol == VpnProtocol.openVpn) {
      return switch (platform) {
        TargetPlatform.linux => 'Requires OpenVPN client + elevation',
        TargetPlatform.windows => 'Requires OpenVPN for Windows (UAC)',
        TargetPlatform.macOS => 'Signed Packet Tunnel build required',
        _ => 'Requires OpenVPN runtime',
      };
    }
    if (protocol == VpnProtocol.ikev2) {
      return switch (platform) {
        TargetPlatform.linux =>
          'Requires OS helper (NetworkManager/strongSwan)',
        TargetPlatform.windows => 'Uses built-in Windows VPN',
        TargetPlatform.macOS => 'NEVPNManager entitlements required',
        _ => 'Uses OS IKEv2/IPsec support',
      };
    }
    return null;
  }

  ({String title, String detail, double progress}) _connectProgress({
    required VpnProtocol? effectiveProtocol,
    required DateTime? lastTunnelStartAt,
    required DateTime? lastProfileFetchAt,
    required bool? lastProfileFetchOk,
  }) {
    final startedAt = lastTunnelStartAt ?? _tickNow;
    final elapsed = _tickNow.difference(startedAt);
    final protocolName =
        effectiveProtocol == null ? 'VPN' : vpnProtocolLabel(effectiveProtocol);
    final profileDone = lastProfileFetchOk == true;
    final profileFailed = lastProfileFetchOk == false;

    if (profileDone && elapsed.inSeconds >= 18) {
      return (
        title: 'Waiting for system tunnel confirmation',
        detail:
            '$protocolName profile is ready. Waiting for the OS helper/runtime to finish establishing the tunnel.',
        progress: 0.9,
      );
    }
    if (profileDone) {
      return (
        title: 'Starting $protocolName runtime',
        detail:
            'Profile received${lastProfileFetchAt != null ? ' at ${_formatClock(lastProfileFetchAt)}' : ''}. Launching the local VPN helper.',
        progress: elapsed.inSeconds >= 8 ? 0.75 : 0.65,
      );
    }
    if (profileFailed) {
      return (
        title: 'Retrying profile setup',
        detail:
            'The app is still trying to prepare a valid profile. Check your connection if this persists.',
        progress: 0.35,
      );
    }
    if (elapsed.inSeconds >= 10) {
      return (
        title: 'Still requesting VPN profile',
        detail:
            'The backend is taking longer than usual to return the $protocolName configuration.',
        progress: 0.25,
      );
    }
    return (
      title: 'Preparing VPN profile',
      detail:
          'Requesting $protocolName configuration and validating runtime requirements.',
      progress: 0.15,
    );
  }

  String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
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
    final protocolMessage =
        ref.watch(vpnStateProvider.select((s) => s.protocolMessage));
    final errorKind = ref.watch(vpnStateProvider.select((s) => s.errorKind));
    final lastProfileFetchAt =
        ref.watch(vpnStateProvider.select((s) => s.lastProfileFetchAt));
    final lastProfileFetchOk =
        ref.watch(vpnStateProvider.select((s) => s.lastProfileFetchOk));
    final lastTunnelStartAt =
        ref.watch(vpnStateProvider.select((s) => s.lastTunnelStartAt));
    final errorMessage = ref.watch(
      vpnStateProvider.select(
        (s) => s.status == VpnStatus.error ? s.errorMessage : null,
      ),
    );
    _syncTimer(status);

    final platform = Theme.of(context).platform;
    final displayProtocol = effectiveProtocol ??
        (selectedProtocol == VpnProtocol.auto ? null : selectedProtocol);
    final protocolLabel = _activeProtocolLabel(
      selected: selectedProtocol,
      effective: effectiveProtocol,
    );
    final helperHint = displayProtocol == null
        ? null
        : _platformHelperHint(platform, displayProtocol);
    final showConnectProgress = status == VpnStatus.connecting;
    final connectProgress = showConnectProgress
        ? _connectProgress(
            effectiveProtocol: effectiveProtocol,
            lastTunnelStartAt: lastTunnelStartAt,
            lastProfileFetchAt: lastProfileFetchAt,
            lastProfileFetchOk: lastProfileFetchOk,
          )
        : null;
    final connectElapsed = showConnectProgress && lastTunnelStartAt != null
        ? _tickNow.difference(lastTunnelStartAt)
        : null;

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

        // ── Protocol in use / selection ─────────────────────────────────
        AnimatedSize(
          duration: AppAnimations.durationNormal,
          curve: AppAnimations.curveDefault,
          child: protocolLabel == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.space2),
                  child: Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    alignment: WrapAlignment.center,
                    children: [
                      Semantics(
                        label: 'Protocol in use: $protocolLabel',
                        child: _InfoPill(
                          icon: Icons.alt_route_rounded,
                          label: protocolLabel,
                          color: AppColors.primary,
                        ),
                      ),
                      if (helperHint != null)
                        Semantics(
                          label: 'Platform helper requirement: $helperHint',
                          child: _InfoPill(
                            icon: Icons.settings_suggest_outlined,
                            label: helperHint,
                            color: AppColors.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
        ),

        if (status != VpnStatus.error &&
            protocolMessage != null &&
            protocolMessage.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.space2),
          Semantics(
            liveRegion: true,
            label: 'Protocol notice: $protocolMessage',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              ),
              child: Text(
                protocolMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],

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

        if (showConnectProgress && connectProgress != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Semantics(
            liveRegion: true,
            label:
                'Connection progress. ${connectProgress.title}. ${connectProgress.detail}',
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space3,
              ),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        size: 16,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: AppSpacing.space2),
                      Expanded(
                        child: Text(
                          connectProgress.title,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (connectElapsed != null)
                        Text(
                          '${connectElapsed.inSeconds}s',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  LinearProgressIndicator(
                    minHeight: 6,
                    value: connectProgress.progress.clamp(0.0, 0.95),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                    backgroundColor:
                        AppColors.secondary.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    connectProgress.detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                          height: 1.25,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── Error message ────────────────────────────────────────────────
        if (status == VpnStatus.error && errorMessage != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Semantics(
            liveRegion: true,
            label: 'VPN error. $errorMessage',
            child: Container(
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.space1),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
