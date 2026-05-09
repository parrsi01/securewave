import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/config/app_config.dart';
import '../../core/models/server_region.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_haptics.dart';
import '../../ui/app_ui_v1.dart';
import '../diagnostics/connection_diagnostics_sheet.dart';
import 'protocol_selection_panel.dart';

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
        return 'Linux VPN uses wg-quick. Install WireGuard tools and allow '
            'the app to run elevated commands when prompted.';
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
    final config = ref.watch(appConfigProvider);

    final serversData =
        servers.maybeWhen(data: (data) => data, orElse: () => null);
    final selectedServer = _selectedServerSummary(
      selectedServerId: vpnState.selectedServerId,
      servers: serversData,
    );

    final backendUnreachable = vpnState.status == VpnStatus.error &&
        vpnState.errorKind == VpnErrorKind.backendUnreachable;
    final statusText = _statusText(vpnState.status, backendUnreachable);
    final statusColor = _statusColor(vpnState.status, backendUnreachable);

    final isConnected = vpnState.status == VpnStatus.connected;
    final isConnecting = vpnState.status == VpnStatus.connecting;
    final isDisconnecting = vpnState.status == VpnStatus.disconnecting;
    final isActive = isConnected || isConnecting || isDisconnecting;
    final platformNotice = _platformNotice();
    final nativeUnavailable = !vpnService.isNativeAvailable;
    final canSimulate = config.useMockApi;
    final canAttemptConnect = !nativeUnavailable || canSimulate;
    final connectEnabled =
        !vpnState.isBusy && (isConnected || canAttemptConnect);

    final connectAction = connectEnabled
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
        : null;

    return SecurePageBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= AppUIv1.tabletBreakpoint;
            final padding = AppUIv1.pagePaddingFor(width);

            return SingleChildScrollView(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppUIv1.shellMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardHeader(
                        statusText: statusText,
                        statusColor: statusColor,
                      ),
                      const SizedBox(height: AppUIv1.space4),
                      ..._noticeCards(
                        nativeUnavailable: nativeUnavailable,
                        canSimulate: canSimulate,
                        platformNotice: platformNotice,
                      ),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _ConnectionControlPanel(
                                vpnState: vpnState,
                                statusText: statusText,
                                statusColor: statusColor,
                                selectedServer: selectedServer,
                                active: isActive,
                                nativeUnavailable: nativeUnavailable,
                                canAttemptConnect: canAttemptConnect,
                                onConnectPressed: connectAction,
                              ),
                            ),
                            const SizedBox(width: AppUIv1.space5),
                            Expanded(
                              flex: 4,
                              child: _SelectionColumn(
                                selectedServer: selectedServer,
                                protocol: vpnState.protocol,
                                onProtocolSelected: (protocol) {
                                  ref
                                      .read(vpnStateProvider.notifier)
                                      .selectProtocol(protocol);
                                },
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _ConnectionControlPanel(
                          vpnState: vpnState,
                          statusText: statusText,
                          statusColor: statusColor,
                          selectedServer: selectedServer,
                          active: isActive,
                          nativeUnavailable: nativeUnavailable,
                          canAttemptConnect: canAttemptConnect,
                          onConnectPressed: connectAction,
                        ),
                        const SizedBox(height: AppUIv1.space4),
                        _SelectionColumn(
                          selectedServer: selectedServer,
                          protocol: vpnState.protocol,
                          onProtocolSelected: (protocol) {
                            ref
                                .read(vpnStateProvider.notifier)
                                .selectProtocol(protocol);
                          },
                        ),
                      ],
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

  List<Widget> _noticeCards({
    required bool nativeUnavailable,
    required bool canSimulate,
    required String? platformNotice,
  }) {
    final needsSetupTitle = platform.operatingSystem == OperatingSystem.macOS
        ? 'VPN unavailable'
        : 'Setup required';
    final cards = <Widget>[];

    if (nativeUnavailable && canSimulate) {
      cards.add(
        const _NoticeCard(
          icon: Icons.info_outline,
          color: AppUIv1.accentSun,
          title: 'Demo mode',
          body: 'Native VPN tunnel unavailable on this device. Connections are '
              'simulated until the native bridge is available.',
        ),
      );
    } else if (nativeUnavailable && platformNotice != null) {
      cards.add(
        _NoticeCard(
          icon: Icons.devices,
          color: AppUIv1.warning,
          title: needsSetupTitle,
          body: platformNotice,
        ),
      );
    } else if (nativeUnavailable) {
      cards.add(
        const _NoticeCard(
          icon: Icons.warning_amber_rounded,
          color: AppUIv1.warning,
          title: 'VPN not available',
          body:
              'Native VPN tunnel unavailable on this device. Install required '
              'VPN components and retry.',
        ),
      );
    }

    if (platformNotice != null && !nativeUnavailable) {
      cards.add(
        _NoticeCard(
          icon: Icons.devices,
          color: AppUIv1.inkSoft,
          title: 'Runtime note',
          body: platformNotice,
        ),
      );
    }

    return [
      for (final card in cards) ...[
        card,
        const SizedBox(height: AppUIv1.space3),
      ],
    ];
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.statusText,
    required this.statusColor,
  });

  final String statusText;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SecureWave control',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppUIv1.space1),
              Text(
                'Operate your tunnel, region, and protocol from one trusted surface.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppUIv1.space3),
        SecureStatePill(
          label: statusText,
          color: statusColor,
          icon: _statusIconForText(statusText),
        ),
      ],
    );
  }
}

class _ConnectionControlPanel extends StatelessWidget {
  const _ConnectionControlPanel({
    required this.vpnState,
    required this.statusText,
    required this.statusColor,
    required this.selectedServer,
    required this.active,
    required this.nativeUnavailable,
    required this.canAttemptConnect,
    required this.onConnectPressed,
  });

  final VpnState vpnState;
  final String statusText;
  final Color statusColor;
  final _SelectedServerSummary selectedServer;
  final bool active;
  final bool nativeUnavailable;
  final bool canAttemptConnect;
  final VoidCallback? onConnectPressed;

  @override
  Widget build(BuildContext context) {
    final stability =
        (vpnState.stabilityScore * 100).clamp(0, 100).round().toString();

    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SecureStatePill(
              label: statusText,
              color: statusColor,
              icon: _statusIcon(vpnState.status),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          _ConnectionRingButton(
            status: vpnState.status,
            statusColor: statusColor,
            isBusy: vpnState.isBusy,
            onPressed: onConnectPressed,
          ),
          const SizedBox(height: AppUIv1.space5),
          AnimatedSwitcher(
            duration: AppUIv1.durationNormal,
            child: Text(
              _connectionHeadline(vpnState.status),
              key: ValueKey(vpnState.status),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppUIv1.space2),
          Text(
            _connectionBody(
              status: vpnState.status,
              nativeUnavailable: nativeUnavailable,
              canAttemptConnect: canAttemptConnect,
            ),
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppUIv1.space4),
            _ErrorBanner(
              message: vpnState.errorMessage!,
              color: statusColor,
              backendUnreachable:
                  vpnState.errorKind == VpnErrorKind.backendUnreachable,
            ),
          ],
          const SizedBox(height: AppUIv1.space5),
          _OperationalBadges(
            selectedServer: selectedServer,
            protocol: vpnState.protocol,
          ),
          const SizedBox(height: AppUIv1.space4),
          AnimatedOpacity(
            duration: AppUIv1.durationNormal,
            opacity: active ? 1 : 0.54,
            child: Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Download',
                    value: '${vpnState.dataRateDown.toStringAsFixed(1)} Mbps',
                  ),
                ),
                const SizedBox(width: AppUIv1.space3),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Upload',
                    value: '${vpnState.dataRateUp.toStringAsFixed(1)} Mbps',
                  ),
                ),
                const SizedBox(width: AppUIv1.space3),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.verified_user_outlined,
                    label: 'Stability',
                    value: '$stability%',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          TextButton.icon(
            onPressed: () => ConnectionDiagnosticsSheet.show(context),
            icon: const Icon(Icons.monitor_heart_outlined, size: 18),
            label: const Text('Connection diagnostics'),
          ),
        ],
      ),
    );
  }
}

class _SelectionColumn extends StatelessWidget {
  const _SelectionColumn({
    required this.selectedServer,
    required this.protocol,
    required this.onProtocolSelected,
  });

  final _SelectedServerSummary selectedServer;
  final VpnProtocol protocol;
  final ValueChanged<VpnProtocol> onProtocolSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ServerSummaryCard(selectedServer: selectedServer),
        const SizedBox(height: AppUIv1.space4),
        SecureSurface(
          variant: SecureSurfaceVariant.base,
          padding: const EdgeInsets.all(AppUIv1.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Protocol', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppUIv1.space1),
              Text(
                'Public release selection remains locked to WireGuard.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppUIv1.space4),
              ProtocolSelectionPanel(
                selectedProtocol: protocol,
                onSelect: onProtocolSelected,
                dense: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerSummaryCard extends StatelessWidget {
  const _ServerSummaryCard({required this.selectedServer});

  final _SelectedServerSummary selectedServer;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.raised,
      padding: const EdgeInsets.all(AppUIv1.space4),
      onTap: () => context.go('/servers'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppUIv1.accentBlue.withValues(alpha: 0.14),
              border: Border.all(color: AppUIv1.borderStrong),
            ),
            child: Icon(
              selectedServer.isAuto
                  ? Icons.auto_awesome_rounded
                  : Icons.public_rounded,
              color: AppUIv1.accent,
            ),
          ),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  selectedServer.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  selectedServer.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppUIv1.inkSoft),
        ],
      ),
    );
  }
}

class _OperationalBadges extends StatelessWidget {
  const _OperationalBadges({
    required this.selectedServer,
    required this.protocol,
  });

  final _SelectedServerSummary selectedServer;
  final VpnProtocol protocol;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final serverBadge = _OperationalBadge(
          icon: selectedServer.isAuto
              ? Icons.auto_awesome_rounded
              : Icons.public_rounded,
          label: 'Server',
          value: selectedServer.label,
        );
        final protocolBadge = _OperationalBadge(
          icon: Icons.hub_outlined,
          label: 'Protocol',
          value: vpnProtocolLabel(protocol),
        );
        if (!stack) {
          return Row(
            children: [
              Expanded(child: serverBadge),
              const SizedBox(width: AppUIv1.space3),
              Expanded(child: protocolBadge),
            ],
          );
        }
        return Column(
          children: [
            serverBadge,
            const SizedBox(height: AppUIv1.space3),
            protocolBadge,
          ],
        );
      },
    );
  }
}

class _OperationalBadge extends StatelessWidget {
  const _OperationalBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        children: [
          Icon(icon, color: AppUIv1.accentCyan, size: 18),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionRingButton extends StatelessWidget {
  const _ConnectionRingButton({
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
    final isDisconnecting = status == VpnStatus.disconnecting;
    final isWorking =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;
    final enabled = onPressed != null;
    final label = isWorking
        ? isDisconnecting
            ? 'Closing'
            : 'Connecting'
        : isConnected
            ? 'Disconnect'
            : 'Connect';
    final icon = isWorking
        ? Icons.sync_rounded
        : isConnected
            ? Icons.stop_rounded
            : Icons.power_settings_new_rounded;

    return AnimatedContainer(
      duration: AppUIv1.durationSlow,
      curve: AppUIv1.curveDefault,
      width: 226,
      height: 226,
      padding: const EdgeInsets.all(AppUIv1.space4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusColor.withValues(alpha: isConnected ? 0.14 : 0.08),
        border: Border.all(color: statusColor.withValues(alpha: 0.26)),
        boxShadow: isConnected ? AppUIv1.glowSuccess : AppUIv1.shadowMd,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space2),
              child: CircularProgressIndicator(
                value: isWorking
                    ? null
                    : isConnected
                        ? 1
                        : status == VpnStatus.error
                            ? 0.72
                            : 0.18,
                strokeWidth: 5,
                color: statusColor,
                backgroundColor: AppUIv1.surfaceMuted.withValues(alpha: 0.72),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          AnimatedScale(
            duration: AppUIv1.durationFast,
            scale: isWorking ? 0.96 : 1,
            child: SizedBox(
              width: 142,
              height: 142,
              child: Material(
                color: enabled
                    ? statusColor.withValues(alpha: isConnected ? 0.92 : 0.96)
                    : AppUIv1.surfaceMuted,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPressed,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.58,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: AppUIv1.durationFast,
                          child: isBusy
                              ? SizedBox(
                                  key: const ValueKey('spinner'),
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppUIv1.background
                                        .withValues(alpha: 0.92),
                                  ),
                                )
                              : Icon(
                                  icon,
                                  key: ValueKey(icon),
                                  color: AppUIv1.background,
                                  size: 34,
                                ),
                        ),
                        const SizedBox(height: AppUIv1.space2),
                        AnimatedSwitcher(
                          duration: AppUIv1.durationFast,
                          child: Text(
                            label,
                            key: ValueKey(label),
                            style: const TextStyle(
                              color: AppUIv1.background,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
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
        ],
      ),
    );
  }
}

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
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                        ),
                  ),
                  const SizedBox(height: AppUIv1.space1),
                ],
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppUIv1.accent),
          const SizedBox(height: AppUIv1.space2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppUIv1.space1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.color,
    required this.backendUnreachable,
  });

  final String message;
  final Color color;
  final bool backendUnreachable;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: backendUnreachable
          ? SecureSurfaceVariant.danger
          : SecureSurfaceVariant.warning,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            backendUnreachable ? Icons.cloud_off : Icons.warning_amber_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Text(
              message,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

_SelectedServerSummary _selectedServerSummary({
  required String? selectedServerId,
  required List<ServerRegion>? servers,
}) {
  if (selectedServerId == null) {
    return const _SelectedServerSummary(
      label: 'Auto-select',
      detail: 'SecureWave chooses the fastest available region.',
      isAuto: true,
    );
  }

  ServerRegion? match;
  for (final server in servers ?? const <ServerRegion>[]) {
    if (server.id == selectedServerId) {
      match = server;
      break;
    }
  }

  if (match == null) {
    return _SelectedServerSummary(
      label: selectedServerId,
      detail: servers == null
          ? 'Saved region. Catalog is still loading.'
          : 'Saved region is not in the current catalog.',
      isAuto: false,
    );
  }

  final detailParts = <String>[];
  if (match.city != null && match.city!.isNotEmpty) {
    detailParts.add(match.city!);
  }
  if (match.country != null && match.country!.isNotEmpty) {
    detailParts.add(match.country!);
  }
  if (match.latencyMs != null) {
    detailParts.add('${match.latencyMs} ms');
  }

  return _SelectedServerSummary(
    label: match.name,
    detail: detailParts.isEmpty ? 'Selected region' : detailParts.join(' • '),
    isAuto: false,
  );
}

String _statusText(VpnStatus status, bool backendUnreachable) {
  return switch (status) {
    VpnStatus.connected => 'Connected',
    VpnStatus.connecting => 'Connecting',
    VpnStatus.disconnecting => 'Disconnecting',
    VpnStatus.error =>
      backendUnreachable ? 'Backend unreachable' : 'Needs attention',
    VpnStatus.disconnected => 'Disconnected',
  };
}

Color _statusColor(VpnStatus status, bool backendUnreachable) {
  return switch (status) {
    VpnStatus.connected => AppUIv1.success,
    VpnStatus.connecting => AppUIv1.accentSun,
    VpnStatus.disconnecting => AppUIv1.accentSun,
    VpnStatus.error => backendUnreachable ? AppUIv1.danger : AppUIv1.warning,
    VpnStatus.disconnected => AppUIv1.accent,
  };
}

IconData _statusIcon(VpnStatus status) {
  return switch (status) {
    VpnStatus.connected => Icons.verified_rounded,
    VpnStatus.connecting => Icons.sync_rounded,
    VpnStatus.disconnecting => Icons.sync_disabled_rounded,
    VpnStatus.error => Icons.warning_amber_rounded,
    VpnStatus.disconnected => Icons.power_settings_new_rounded,
  };
}

IconData _statusIconForText(String statusText) {
  if (statusText.contains('Connected')) return Icons.verified_rounded;
  if (statusText.contains('Connecting')) return Icons.sync_rounded;
  if (statusText.contains('attention') || statusText.contains('unreachable')) {
    return Icons.warning_amber_rounded;
  }
  return Icons.power_settings_new_rounded;
}

String _connectionHeadline(VpnStatus status) {
  return switch (status) {
    VpnStatus.connected => 'Protected tunnel active',
    VpnStatus.connecting => 'Establishing secure tunnel',
    VpnStatus.disconnecting => 'Closing tunnel cleanly',
    VpnStatus.error => 'Connection needs attention',
    VpnStatus.disconnected => 'Ready to secure traffic',
  };
}

String _connectionBody({
  required VpnStatus status,
  required bool nativeUnavailable,
  required bool canAttemptConnect,
}) {
  if (!canAttemptConnect) {
    return 'Native VPN support is required before this device can open a real tunnel.';
  }
  return switch (status) {
    VpnStatus.connected =>
      'Your selected tunnel is active. Live throughput reflects the current app state.',
    VpnStatus.connecting =>
      'SecureWave is requesting the profile and starting the tunnel.',
    VpnStatus.disconnecting =>
      'SecureWave is stopping the tunnel and clearing active transfer rates.',
    VpnStatus.error =>
      'Review the message below or open diagnostics for a read-only health check.',
    VpnStatus.disconnected => nativeUnavailable
        ? 'Demo mode can simulate the flow, but native VPN support is not active here.'
        : 'Choose a region and press Connect when you are ready.',
  };
}

class _SelectedServerSummary {
  const _SelectedServerSummary({
    required this.label,
    required this.detail,
    required this.isAuto,
  });

  final String label;
  final String detail;
  final bool isAuto;
}
