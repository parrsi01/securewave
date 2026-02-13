import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../diagnostics/connection_diagnostics_sheet.dart';
import '../../ui/app_haptics.dart';
import '../../ui/app_ui_v1.dart';

class VpnPage extends ConsumerStatefulWidget {
  const VpnPage({super.key});

  @override
  ConsumerState<VpnPage> createState() => _VpnPageState();
}

class _VpnPageState extends ConsumerState<VpnPage> {
  bool _pendingConnectHaptic = false;
  bool _pendingDisconnectHaptic = false;
  late final ProviderSubscription<VpnStatus> _statusSubscription;

  String? _platformNotice() {
    final os = platform.operatingSystem;
    if (kIsWeb) {
      return 'VPN tunnels cannot run inside a web browser. Download the native app.';
    }
    switch (os) {
      case OperatingSystem.linux:
        return 'Linux VPN uses wg-quick and requires elevation (PolicyKit/pkexec). '
            'Install WireGuard tools and approve the system prompt when connecting.';
      case OperatingSystem.windows:
        return 'Windows VPN requires WireGuard for Windows (wireguard.exe). '
            'Install it to enable native tunneling.';
      case OperatingSystem.macOS:
        return 'VPN unavailable on macOS (yet). This build does not include the '
            'required Apple Network Extension entitlements for real tunneling.';
      case OperatingSystem.iOS:
      case OperatingSystem.android:
        return null;
      default:
        return 'This platform is not supported for VPN tunnels.';
    }
  }

  @override
  void initState() {
    super.initState();
    _statusSubscription = ref.listenManual<VpnStatus>(
      vpnStateProvider.select((state) => state.status),
      (prev, next) {
        if (prev == next) return;
        if (next == VpnStatus.connected && _pendingConnectHaptic) {
          _pendingConnectHaptic = false;
          unawaited(AppHaptics.connectConfirmed());
          return;
        }
        if (next == VpnStatus.disconnected && _pendingDisconnectHaptic) {
          _pendingDisconnectHaptic = false;
          unawaited(AppHaptics.disconnectConfirmed());
          return;
        }
        if (next == VpnStatus.error) {
          _pendingConnectHaptic = false;
          _pendingDisconnectHaptic = false;
        }
      },
    );
  }

  @override
  void dispose() {
    _statusSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final vpnService = ref.watch(vpnServiceProvider);
    final serversData =
        servers.maybeWhen(data: (data) => data, orElse: () => null);

    final selectedServerLabel = vpnState.selectedServerId == null
        ? 'Auto-select'
        : (serversData == null || serversData.isEmpty)
            ? vpnState.selectedServerId!
            : serversData
                .firstWhere(
                  (server) => server.id == vpnState.selectedServerId,
                  orElse: () => serversData.first,
                )
                .name;

    final statusText = vpnState.statusText(includeEllipsis: true);
    final statusColor = vpnState.statusColor;

    final isConnected = vpnState.status == VpnStatus.connected;
    final isConnecting = vpnState.status == VpnStatus.connecting;
    final isDisconnecting = vpnState.status == VpnStatus.disconnecting;
    final platformNotice = _platformNotice();
    final nativeUnavailable = !vpnService.isNativeAvailable;
    final canAttemptConnect = !nativeUnavailable;
    final connectEnabled =
        !vpnState.isBusy && (isConnected || canAttemptConnect);
    final needsSetupTitle = platform.operatingSystem == OperatingSystem.macOS
        ? 'VPN unavailable'
        : 'Setup required';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppUIv1.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppUIv1.space5,
              vertical: AppUIv1.space4,
            ),
            children: [
              // ── Notices (collapsed if none) ───────────────────────
              if (nativeUnavailable && platformNotice != null) ...[
                _NoticeCard(
                  icon: Icons.devices,
                  color: AppUIv1.warning,
                  title: needsSetupTitle,
                  body: platformNotice,
                ),
                const SizedBox(height: AppUIv1.space3),
              ] else if (nativeUnavailable) ...[
                const _NoticeCard(
                  icon: Icons.warning_amber_rounded,
                  color: AppUIv1.warning,
                  title: 'VPN not available',
                  body:
                      'Native VPN tunnel unavailable on this device. Install required VPN components and retry.',
                ),
                const SizedBox(height: AppUIv1.space3),
              ],
              if (platformNotice != null && !nativeUnavailable) ...[
                _NoticeCard(
                  icon: Icons.devices,
                  color: AppUIv1.inkSoft,
                  body: platformNotice,
                ),
                const SizedBox(height: AppUIv1.space3),
              ],

              // ── Hero connection section ───────────────────────────
              const SizedBox(height: AppUIv1.space4),
              Center(
                child: _ConnectButton(
                  status: vpnState.status,
                  statusColor: statusColor,
                  isBusy: vpnState.isBusy,
                  onPressed: connectEnabled
                      ? () {
                          if (isConnected) {
                            _pendingDisconnectHaptic = true;
                            _pendingConnectHaptic = false;
                            unawaited(AppHaptics.disconnectTap());
                            ref.read(vpnStateProvider.notifier).disconnect();
                          } else {
                            _pendingConnectHaptic = true;
                            _pendingDisconnectHaptic = false;
                            unawaited(AppHaptics.connectTap());
                            ref.read(vpnStateProvider.notifier).connect();
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Status label ──────────────────────────────────────
              Center(
                child: AnimatedSwitcher(
                  duration: AppUIv1.durationNormal,
                  child: Text(
                    statusText,
                    key: ValueKey('${vpnState.status}_${vpnState.errorKind}'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: statusColor,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: AppUIv1.space2),
              Center(
                child: TextButton.icon(
                  onPressed: () => ConnectionDiagnosticsSheet.show(context),
                  icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                  label: const Text('Connection diagnostics'),
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Server selection row ──────────────────────────────
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppUIv1.radiusXL),
                  onTap: () => context.go('/servers'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppUIv1.space4,
                      vertical: AppUIv1.space3,
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: AppUIv1.accentSoft,
                          child: Icon(Icons.public,
                              size: 20, color: AppUIv1.accent),
                        ),
                        const SizedBox(width: AppUIv1.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Server',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                selectedServerLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Error message ─────────────────────────────────────
              if (vpnState.errorMessage != null) ...[
                const SizedBox(height: AppUIv1.space3),
                Container(
                  padding: const EdgeInsets.all(AppUIv1.space3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppUIv1.radiusM),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        vpnState.statusIcon,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: AppUIv1.space2),
                      Expanded(
                        child: Text(
                          vpnState.errorMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Live activity ─────────────────────────────────────
              const SizedBox(height: AppUIv1.space4),
              AnimatedOpacity(
                duration: AppUIv1.durationNormal,
                opacity:
                    isConnected || isConnecting || isDisconnecting ? 1.0 : 0.4,
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_downward_rounded,
                        label: 'Download',
                        value: isConnected
                            ? '${vpnState.dataRateDown.toStringAsFixed(1)} Mbps'
                            : '--',
                      ),
                    ),
                    const SizedBox(width: AppUIv1.space3),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_upward_rounded,
                        label: 'Upload',
                        value: isConnected
                            ? '${vpnState.dataRateUp.toStringAsFixed(1)} Mbps'
                            : '--',
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
  }
}

// ── Hero connect button ────────────────────────────────────────────────

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.status,
    required this.statusColor,
    required this.isBusy,
    required this.onPressed,
  });

  final VpnStatus status;
  final Color statusColor;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isConnected = status == VpnStatus.connected;
    final isWorking =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;
    final isDisconnecting = status == VpnStatus.disconnecting;
    final isDisabled = onPressed == null && !isWorking;
    final buttonColor = isDisabled
        ? AppUIv1.inkSoft
        : (isConnected || isDisconnecting)
            ? AppUIv1.success
            : AppUIv1.accent;
    final ringColor = statusColor.withValues(alpha: isDisabled ? 0.08 : 0.15);

    final label = isWorking
        ? isDisconnecting
            ? 'Disconnecting'
            : 'Connecting'
        : isConnected
            ? 'Disconnect'
            : 'Connect';

    final icon = isWorking
        ? Icons.sync
        : isConnected
            ? Icons.stop_rounded
            : Icons.power_settings_new_rounded;

    return AnimatedOpacity(
      duration: AppUIv1.durationNormal,
      opacity: isDisabled ? 0.45 : 1.0,
      child: AnimatedContainer(
      duration: AppUIv1.durationSlow,
      curve: AppUIv1.curveDefault,
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringColor,
        boxShadow: isConnected
            ? [
                BoxShadow(
                  color: AppUIv1.success.withValues(alpha: 0.15),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ]
            : [],
      ),
      child: Center(
        child: AnimatedContainer(
          duration: AppUIv1.durationNormal,
          curve: AppUIv1.curveDefault,
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: buttonColor,
            boxShadow: AppUIv1.shadowMd,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: AppUIv1.durationFast,
                    child: isWorking
                        ? SizedBox(
                            key: const ValueKey('spinner'),
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          )
                        : Icon(icon,
                            key: ValueKey(icon), color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: AppUIv1.durationFast,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
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
  }
}

// ── Notice card ────────────────────────────────────────────────────────

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.body,
    this.title,
  });

  final IconData icon;
  final Color color;
  final String body;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppUIv1.space3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppUIv1.radiusM),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metric tile ────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppUIv1.space3),
      decoration: BoxDecoration(
        color: AppUIv1.surface,
        borderRadius: BorderRadius.circular(AppUIv1.radiusL),
        border: Border.all(color: AppUIv1.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppUIv1.accent),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
