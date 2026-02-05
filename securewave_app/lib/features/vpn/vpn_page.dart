import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  String? _platformNotice() {
    final os = platform.operatingSystem;
    if (kIsWeb) {
      return 'VPN tunnels cannot run inside a web browser. Download the native app.';
    }
    switch (os) {
      case OperatingSystem.linux:
        return 'Linux VPN uses wg-quick. Install WireGuard tools and allow '
            'the app to run elevated commands when prompted.';
      case OperatingSystem.windows:
        return 'Windows VPN requires WireGuard for Windows (wireguard.exe). '
            'Install it to enable native tunneling.';
      case OperatingSystem.macOS:
        return 'macOS VPN support is coming soon. The app requires additional '
            'Apple approvals before VPN tunnels can be established on Mac.';
      case OperatingSystem.iOS:
      case OperatingSystem.android:
        return null;
      default:
        return 'This platform is not supported for VPN tunnels.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final vpnService = ref.watch(vpnServiceProvider);

    final serversData =
        servers.maybeWhen(data: (data) => data, orElse: () => null);
    if (serversData != null &&
        serversData.isNotEmpty &&
        vpnState.selectedServerId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(vpnStateProvider.notifier).selectServer(serversData.first.id);
      });
    }

    final selectedServerLabel = serversData == null || serversData.isEmpty
        ? 'Auto-select'
        : serversData
                .firstWhere(
                  (server) => server.id == vpnState.selectedServerId,
                  orElse: () => serversData.first,
                )
                .name;

    final statusText = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting...',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.error => AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };

    final isConnected = vpnState.status == VpnStatus.connected;
    final isConnecting = vpnState.status == VpnStatus.connecting;
    final platformNotice = _platformNotice();
    final nativeUnavailable = !vpnService.isNativeAvailable;

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
              if (nativeUnavailable) ...[
                const _NoticeCard(
                  icon: Icons.info_outline,
                  color: AppUIv1.accentSun,
                  title: 'Demo mode',
                  body: 'Native VPN tunnel unavailable on this device. '
                      'Connections are simulated. Install the native bridge '
                      'for real tunnel support.',
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
                  onPressed: vpnState.isBusy
                      ? null
                      : () {
                          if (isConnected) {
                            ref.read(vpnStateProvider.notifier).disconnect();
                          } else {
                            ref.read(vpnStateProvider.notifier).connect();
                          }
                        },
                ),
              ),
              const SizedBox(height: AppUIv1.space5),

              // ── Status label ──────────────────────────────────────
              Center(
                child: AnimatedSwitcher(
                  duration: AppUIv1.durationNormal,
                  child: Text(
                    statusText,
                    key: ValueKey(vpnState.status),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: statusColor,
                        ),
                  ),
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
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: AppUIv1.inkSoft),
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
                    color: AppUIv1.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppUIv1.radiusM),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: AppUIv1.warning),
                      const SizedBox(width: AppUIv1.space2),
                      Expanded(
                        child: Text(
                          vpnState.errorMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppUIv1.warning),
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
                opacity: isConnected || isConnecting ? 1.0 : 0.4,
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_downward_rounded,
                        label: 'Download',
                        value:
                            '${vpnState.dataRateDown.toStringAsFixed(1)} Mbps',
                      ),
                    ),
                    const SizedBox(width: AppUIv1.space3),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_upward_rounded,
                        label: 'Upload',
                        value:
                            '${vpnState.dataRateUp.toStringAsFixed(1)} Mbps',
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
    final isConnecting = status == VpnStatus.connecting;
    final buttonColor = isConnected ? AppUIv1.success : AppUIv1.accent;
    final ringColor = statusColor.withValues(alpha: 0.15);

    final label = isConnecting
        ? 'Connecting'
        : isConnected
            ? 'Disconnect'
            : 'Connect';

    final icon = isConnecting
        ? Icons.sync
        : isConnected
            ? Icons.stop_rounded
            : Icons.power_settings_new_rounded;

    return GestureDetector(
      onTap: onPressed,
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
                    if (isConnecting)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      )
                    else
                      Icon(icon, color: Colors.white, size: 32),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
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
