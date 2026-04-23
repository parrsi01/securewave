import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/config/app_config.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_haptics.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';
import '../diagnostics/connection_diagnostics_sheet.dart';

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
        return 'Linux VPN uses wg-quick. Install WireGuard tools and allow elevated tunnel commands.';
      case OperatingSystem.windows:
        return 'Windows VPN requires WireGuard for Windows (wireguard.exe).';
      case OperatingSystem.macOS:
        return 'VPN unavailable on macOS. This build does not include Network Extension tunnel support.';
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
    final platformNotice = _platformNotice();

    final serversData = servers.maybeWhen(
      data: (data) => data,
      orElse: () => null,
    );
    final selectedServerLabel = vpnState.selectedServerId == null
        ? 'Smart location'
        : (serversData == null || serversData.isEmpty)
        ? vpnState.selectedServerId!
        : serversData
              .firstWhere(
                (server) => server.id == vpnState.selectedServerId,
                orElse: () => serversData.first,
              )
              .name;

    final backendUnreachable =
        vpnState.status == VpnStatus.error &&
        vpnState.errorKind == VpnErrorKind.backendUnreachable;
    final statusText = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error =>
        backendUnreachable ? 'Backend unreachable' : 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };
    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentCyan,
      VpnStatus.disconnecting => AppUIv1.warning,
      VpnStatus.error => backendUnreachable ? AppUIv1.danger : AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };

    final isConnected = vpnState.status == VpnStatus.connected;
    final isConnecting = vpnState.status == VpnStatus.connecting;
    final isDisconnecting = vpnState.status == VpnStatus.disconnecting;
    final nativeUnavailable = !vpnService.isNativeAvailable;
    final canSimulate = config.useMockApi;
    final canAttemptConnect = !nativeUnavailable || canSimulate;
    final connectEnabled =
        !vpnState.isBusy && (isConnected || canAttemptConnect);

    return SwPage(
      center: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppUIv1.desktopBreakpoint;
          final dashboard = Column(
            children: [
              SwSectionHeader(
                eyebrow: 'Dashboard',
                title: 'Secure tunnel control',
                subtitle:
                    'Live VPN state, protocol truth, location, diagnostics, and traffic telemetry.',
                trailing: SwStatusPill(
                  label: statusText,
                  color: statusColor,
                  icon: _statusIcon(vpnState.status),
                  pulse: isConnecting || isDisconnecting,
                ),
              ),
              const SizedBox(height: AppUIv1.space5),
              if (nativeUnavailable || platformNotice != null)
                _NoticeSurface(
                  nativeUnavailable: nativeUnavailable,
                  canSimulate: canSimulate,
                  platformNotice: platformNotice,
                ),
              if (nativeUnavailable || platformNotice != null)
                const SizedBox(height: AppUIv1.space4),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _ConnectionStage(
                        vpnState: vpnState,
                        statusText: statusText,
                        statusColor: statusColor,
                        selectedServerLabel: selectedServerLabel,
                        connectEnabled: connectEnabled,
                        onConnectPressed: () =>
                            _handleConnectToggle(isConnected),
                      ),
                    ),
                    const SizedBox(width: AppUIv1.space4),
                    Expanded(
                      flex: 4,
                      child: _SideColumn(
                        vpnState: vpnState,
                        statusColor: statusColor,
                        selectedServerLabel: selectedServerLabel,
                      ),
                    ),
                  ],
                )
              else ...[
                _ConnectionStage(
                  vpnState: vpnState,
                  statusText: statusText,
                  statusColor: statusColor,
                  selectedServerLabel: selectedServerLabel,
                  connectEnabled: connectEnabled,
                  onConnectPressed: () => _handleConnectToggle(isConnected),
                ),
                const SizedBox(height: AppUIv1.space4),
                _SideColumn(
                  vpnState: vpnState,
                  statusColor: statusColor,
                  selectedServerLabel: selectedServerLabel,
                ),
              ],
            ],
          );
          return ListView(children: [dashboard]);
        },
      ),
    );
  }

  void _handleConnectToggle(bool isConnected) {
    if (isConnected) {
      _pendingDisconnectHaptic = true;
      _pendingConnectHaptic = false;
      unawaited(AppHaptics.disconnectTap());
      ref.read(vpnStateProvider.notifier).disconnect();
      return;
    }
    _pendingConnectHaptic = true;
    _pendingDisconnectHaptic = false;
    unawaited(AppHaptics.connectTap());
    ref.read(vpnStateProvider.notifier).connect();
  }

  IconData _statusIcon(VpnStatus status) {
    return switch (status) {
      VpnStatus.connected => Icons.verified_user_rounded,
      VpnStatus.connecting => Icons.sync_rounded,
      VpnStatus.disconnecting => Icons.sync_disabled_rounded,
      VpnStatus.error => Icons.warning_amber_rounded,
      VpnStatus.disconnected => Icons.shield_outlined,
    };
  }
}

class _ConnectionStage extends StatelessWidget {
  const _ConnectionStage({
    required this.vpnState,
    required this.statusText,
    required this.statusColor,
    required this.selectedServerLabel,
    required this.connectEnabled,
    required this.onConnectPressed,
  });

  final VpnState vpnState;
  final String statusText;
  final Color statusColor;
  final String selectedServerLabel;
  final bool connectEnabled;
  final VoidCallback onConnectPressed;

  @override
  Widget build(BuildContext context) {
    final isConnected = vpnState.status == VpnStatus.connected;
    final isBusy =
        vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.disconnecting;

    return SwPanel(
      accent: statusColor,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 360,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WorldTracePainter(color: statusColor),
                ),
              ),
              _ConnectCore(
                status: vpnState.status,
                color: statusColor,
                enabled: connectEnabled,
                onPressed: connectEnabled ? onConnectPressed : null,
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: AppUIv1.durationNormal,
            child: Column(
              key: ValueKey(vpnState.status),
              children: [
                Text(
                  statusText.toUpperCase(),
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: statusColor),
                ),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  isConnected
                      ? 'Your connection is secured by the active tunnel.'
                      : isBusy
                      ? 'SecureWave is negotiating tunnel state.'
                      : 'Tap the core to connect securely.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space5),
          _ConnectionToolbar(
            selectedServerLabel: selectedServerLabel,
            protocol: vpnProtocolLabel(vpnState.protocol),
          ),
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppUIv1.space4),
            SwPanel(
              accent: statusColor,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: statusColor),
                  const SizedBox(width: AppUIv1.space3),
                  Expanded(
                    child: Text(
                      vpnState.errorMessage!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: statusColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectCore extends StatefulWidget {
  const _ConnectCore({
    required this.status,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  final VpnStatus status;
  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<_ConnectCore> createState() => _ConnectCoreState();
}

class _ConnectCoreState extends State<_ConnectCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.status == VpnStatus.connected;
    final isBusy =
        widget.status == VpnStatus.connecting ||
        widget.status == VpnStatus.disconnecting;
    final icon = isBusy
        ? Icons.sync_rounded
        : isConnected
        ? Icons.stop_rounded
        : Icons.power_settings_new_rounded;
    final label = isBusy
        ? widget.status == VpnStatus.disconnecting
              ? 'Closing'
              : 'Linking'
        : isConnected
        ? 'Disconnect'
        : 'Connect';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 238,
          height: 238,
          child: CustomPaint(
            painter: _CoreRingPainter(
              progress: _controller.value,
              color: widget.color,
              busy: isBusy,
              connected: isConnected,
            ),
            child: Center(
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.enabled ? widget.onPressed : null,
                  child: AnimatedContainer(
                    duration: AppUIv1.durationNormal,
                    curve: AppUIv1.curveDefault,
                    width: 126,
                    height: 126,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isConnected
                          ? const LinearGradient(
                              colors: [AppUIv1.accentTeal, AppUIv1.success],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : AppUIv1.brandGradient,
                      boxShadow: AppUIv1.glow(widget.color, opacity: 0.42),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        isBusy
                            ? RotationTransition(
                                turns: _controller,
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              )
                            : Icon(icon, color: Colors.white, size: 34),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoreRingPainter extends CustomPainter {
  const _CoreRingPainter({
    required this.progress,
    required this.color,
    required this.busy,
    required this.connected,
  });

  final double progress;
  final Color color;
  final bool busy;
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 4; i++) {
      final radius = 58.0 + i * 24;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 1 ? 1.4 : 0.8
          ..color = color.withValues(alpha: 0.22 - i * 0.035),
      );
    }
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          color,
          AppUIv1.accentTeal,
          Colors.transparent,
        ],
        stops: const [0, 0.35, 0.70, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, 102, sweep);
    if (busy || connected) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 80),
        progress * math.pi * 2,
        busy ? 1.4 : math.pi * 1.65,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.busy != busy ||
        oldDelegate.connected != connected;
  }
}

class _WorldTracePainter extends CustomPainter {
  const _WorldTracePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = AppUIv1.borderStrong.withValues(alpha: 0.26);
    final centerY = size.height * 0.45;
    for (var i = 0; i < 5; i++) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, centerY),
        width: size.width * (0.42 + i * 0.14),
        height: size.height * (0.18 + i * 0.08),
      );
      canvas.drawOval(rect, paint);
    }
    final nodePaint = Paint()..color = color.withValues(alpha: 0.70);
    for (final offset in const [
      Offset(0.22, 0.34),
      Offset(0.38, 0.24),
      Offset(0.62, 0.30),
      Offset(0.78, 0.48),
      Offset(0.31, 0.62),
      Offset(0.68, 0.66),
    ]) {
      canvas.drawCircle(
        Offset(size.width * offset.dx, size.height * offset.dy),
        2.4,
        nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WorldTracePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ConnectionToolbar extends StatelessWidget {
  const _ConnectionToolbar({
    required this.selectedServerLabel,
    required this.protocol,
  });

  final String selectedServerLabel;
  final String protocol;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final tiles = [
          SwActionTile(
            icon: Icons.travel_explore,
            title: selectedServerLabel,
            subtitle: 'Location policy',
            color: AppUIv1.accentCyan,
            onTap: () => context.go('/servers'),
            trailing: const Icon(Icons.chevron_right, color: AppUIv1.inkSoft),
          ),
          SwActionTile(
            icon: Icons.hub_outlined,
            title: protocol,
            subtitle: 'Active protocol',
            color: AppUIv1.accentTeal,
          ),
          SwActionTile(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostics',
            subtitle: 'Readiness scan',
            color: AppUIv1.accentViolet,
            onTap: () => ConnectionDiagnosticsSheet.show(context),
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: AppUIv1.space3),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final tile in tiles) ...[
              Expanded(child: tile),
              if (tile != tiles.last) const SizedBox(width: AppUIv1.space3),
            ],
          ],
        );
      },
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.vpnState,
    required this.statusColor,
    required this.selectedServerLabel,
  });

  final VpnState vpnState;
  final Color statusColor;
  final String selectedServerLabel;

  @override
  Widget build(BuildContext context) {
    final active =
        vpnState.status == VpnStatus.connected ||
        vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.disconnecting;
    return Column(
      children: [
        SwPanel(
          accent: statusColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection Status',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppUIv1.space4),
              _DetailRow('Protocol', vpnProtocolLabel(vpnState.protocol)),
              _DetailRow('Location', selectedServerLabel),
              _DetailRow('Tunnel state', vpnState.status.name),
              _DetailRow('Traffic source', active ? 'Live session' : 'Idle'),
            ],
          ),
        ),
        const SizedBox(height: AppUIv1.space4),
        AnimatedOpacity(
          duration: AppUIv1.durationNormal,
          opacity: active ? 1 : 0.45,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 480;
              final metrics = [
                SwMetricTile(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Download',
                  value: '${vpnState.dataRateDown.toStringAsFixed(1)} Mbps',
                  color: AppUIv1.accentCyan,
                  caption: 'Current rate',
                ),
                SwMetricTile(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Upload',
                  value: '${vpnState.dataRateUp.toStringAsFixed(1)} Mbps',
                  color: AppUIv1.accentTeal,
                  caption: 'Current rate',
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    metrics[0],
                    const SizedBox(height: AppUIv1.space3),
                    metrics[1],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: metrics[0]),
                  const SizedBox(width: AppUIv1.space3),
                  Expanded(child: metrics[1]),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppUIv1.space4),
        SwPanel(
          accent: AppUIv1.accentViolet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Network Activity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppUIv1.space3),
              const SwMiniGraph(color: AppUIv1.accentCyan),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUIv1.space3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeSurface extends StatelessWidget {
  const _NoticeSurface({
    required this.nativeUnavailable,
    required this.canSimulate,
    required this.platformNotice,
  });

  final bool nativeUnavailable;
  final bool canSimulate;
  final String? platformNotice;

  @override
  Widget build(BuildContext context) {
    final title = nativeUnavailable && canSimulate
        ? 'Demo mode active'
        : nativeUnavailable
        ? 'Native tunnel unavailable'
        : 'Platform note';
    final body = nativeUnavailable && canSimulate
        ? 'Native VPN tunnel unavailable on this device. Connections are simulated because mock API mode is enabled.'
        : platformNotice ?? 'Review platform prerequisites before connecting.';
    final color = nativeUnavailable ? AppUIv1.warning : AppUIv1.inkSoft;
    return SwPanel(
      accent: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppUIv1.space1),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
