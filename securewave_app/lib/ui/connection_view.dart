import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/vpn_service.dart' show VpnStatus;
import 'auth_form.dart';
import 'theme.dart';
import 'transfer_summary.dart';

/// An explicit presentation mapping. Unrecognized native output is never shown.
String safeVpnMessage(String message, {required bool canDisconnect}) {
  const known = {
    'Your 5 GB monthly allowance is used. It renews next month (UTC).':
        'Your 5 GB monthly allowance is used. It renews next month (UTC).',
    'Unable to reach SecureWave. Check your connection and try again.':
        'Unable to reach SecureWave. Check your connection and try again.',
    'SecureWave server error.': 'SecureWave server error.',
    'The Linux WireGuard helper is unavailable.':
        'The Linux WireGuard helper is unavailable.',
    'SecureWave VPN is available on Linux only.':
        'SecureWave VPN is available on Linux only.',
    'The previous VPN session could not be verified.':
        'The previous VPN session could not be verified.',
    'Could not safely restore the normal internet connection.':
        'SecureWave could not safely restore normal internet access.',
    'Normal internet access was not restored after disconnect.':
        'SecureWave could not safely restore normal internet access.',
    'Could not disconnect the WireGuard tunnel.':
        'SecureWave could not safely restore normal internet access.',
    'WireGuard interface is not active.':
        'The VPN connection could not be verified.',
    'The expected WireGuard peer is not configured.':
        'The VPN connection could not be verified.',
    'WireGuard has no recent peer handshake.':
        'The VPN connection could not be verified.',
    'WireGuard interface counters are unavailable.':
        'The VPN connection could not be verified.',
    'WireGuard traffic counters are unavailable.':
        'The VPN connection could not be verified.',
    'The VPN internet route is not active.':
        'The VPN connection could not be verified.',
    'VPN egress did not change.': 'The VPN connection could not be verified.',
  };
  return known[message] ??
      (canDisconnect
          ? 'SecureWave couldn’t complete disconnection.'
          : 'SecureWave couldn’t establish the VPN connection.');
}

/// Receives authoritative Home values; does not own or infer VPN state.
class ConnectionView extends StatelessWidget {
  const ConnectionView({
    super.key,
    required this.status,
    required this.canDisconnect,
    required this.transitioning,
    required this.serverLabel,
    required this.download,
    required this.upload,
    required this.countersAvailable,
    required this.onToggle,
    required this.onLogout,
    this.error,
    this.recordingNotice,
    this.monthlyUsage,
    this.onSettings,
    this.sessionLabel = 'Session transfer',
  });
  final VpnStatus status;
  final bool canDisconnect;
  final bool transitioning;
  final String serverLabel;
  final String download;
  final String upload;
  final bool countersAvailable;
  final VoidCallback onToggle;
  final VoidCallback onLogout;
  final String? error;
  final String? recordingNotice;
  final Widget? monthlyUsage;
  final VoidCallback? onSettings;
  final String sessionLabel;

  String get action => switch (status) {
        VpnStatus.connecting => 'Connecting',
        VpnStatus.disconnecting => 'Disconnecting',
        _ => canDisconnect
            ? 'Disconnect'
            : status == VpnStatus.error
                ? 'Try again'
                : 'Connect',
      };

  String get headline => switch (status) {
        VpnStatus.disconnected => 'Disconnected',
        VpnStatus.connecting => 'Connecting',
        VpnStatus.connected => 'Connected',
        VpnStatus.disconnecting => 'Disconnecting',
        VpnStatus.error => 'Connection error',
      };

  Color get stateColor => switch (status) {
        VpnStatus.connected => AppTheme.connected,
        VpnStatus.error => AppTheme.error,
        VpnStatus.disconnected => AppTheme.disconnected,
        _ => AppTheme.textPrimary,
      };

  IconData get statusIcon => switch (status) {
        VpnStatus.connected => Icons.check_circle_outline,
        VpnStatus.error => Icons.error_outline,
        VpnStatus.disconnected => Icons.circle_outlined,
        _ => Icons.hourglass_empty,
      };

  String get productLabel {
    final label = serverLabel.trim();
    return label.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(label)
        ? 'SecureWave Network'
        : label;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, viewport) {
            final padding = AppTheme.outerPadding(viewport.maxWidth);
            final compact = viewport.maxWidth < 640;
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final logout = TextButton(
              key: const ValueKey('logout'),
              onPressed: transitioning ? null : onLogout,
              child: const Text('Log out'),
            );
            final settings = MergeSemantics(
              child: Semantics(
                label: 'Settings',
                button: true,
                child: IconButton(
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
            );
            final header = ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56, maxWidth: 960),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                child: viewport.maxWidth < 400 && scale >= 1.5
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            const BrandWordmark(),
                            Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (onSettings != null) settings,
                                      logout,
                                    ]))
                          ])
                    : Row(children: [
                        const Expanded(child: BrandWordmark()),
                        if (onSettings != null) settings,
                        logout,
                      ]),
              ),
            );
            return Column(children: [
              Center(child: header),
              const Divider(),
              Expanded(
                child: LayoutBuilder(builder: (context, body) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight:
                              (body.maxHeight - 32).clamp(0, double.infinity)),
                      child: Align(
                        alignment: viewport.maxHeight < 640
                            ? Alignment.topCenter
                            : Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Semantics(
                                  key: const ValueKey('vpn-state'),
                                  liveRegion: true,
                                  label: status == VpnStatus.error
                                      ? 'VPN connection error.'
                                      : 'VPN ${headline.toLowerCase()}.',
                                  excludeSemantics: true,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(statusIcon,
                                          size: 20, color: stateColor),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: AnimatedSwitcher(
                                          duration:
                                              AppTheme.reduceMotion(context)
                                                  ? Duration.zero
                                                  : AppTheme.stateDuration,
                                          child: Text(headline,
                                              key: ValueKey(headline),
                                              textAlign: TextAlign.center,
                                              style: AppTheme.type(
                                                  compact ? 32 : 40, 600, 1.2,
                                                  color: stateColor,
                                                  spacing: -.6)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _ConnectionControl(
                                  status: status,
                                  action: action,
                                  compact: compact,
                                  disabled: transitioning,
                                  onPressed: onToggle,
                                ),
                                if (error != null) ...[
                                  const SizedBox(height: 16),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 420),
                                    child: UiFeedback(safeVpnMessage(error!,
                                        canDisconnect: canDisconnect)),
                                  ),
                                  const SizedBox(height: 16),
                                ] else
                                  const SizedBox(height: 32),
                                _ConnectionInformation(
                                  productLabel: productLabel,
                                  compact: compact,
                                  download: download,
                                  upload: upload,
                                  countersAvailable: countersAvailable,
                                  recordingNotice: recordingNotice,
                                  monthlyUsage: monthlyUsage,
                                  sessionLabel: sessionLabel,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ]);
          }),
        ),
      );
}

/// The existing location, protocol and recorded totals share one surface.
/// This widget receives values only and never queries runtime state.
class _ConnectionInformation extends StatelessWidget {
  const _ConnectionInformation({
    required this.productLabel,
    required this.compact,
    required this.download,
    required this.upload,
    required this.countersAvailable,
    this.recordingNotice,
    this.monthlyUsage,
    required this.sessionLabel,
  });

  final String productLabel;
  final bool compact;
  final String download;
  final String upload;
  final bool countersAvailable;
  final String? recordingNotice;
  final Widget? monthlyUsage;
  final String sessionLabel;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('connection-information'),
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 16 : 24),
        decoration: BoxDecoration(
          color: AppTheme.surfacePrimary,
          border: Border.all(color: AppTheme.borderSubtle),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
              final location = Semantics(
                label: 'Server label: $productLabel. SecureWave Network.',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(productLabel, style: AppTheme.sectionTitle),
                    if (productLabel != 'SecureWave Network') ...[
                      const SizedBox(height: 4),
                      Text('SecureWave Network', style: AppTheme.caption),
                    ],
                  ],
                ),
              );
              final protocol = Semantics(
                label: 'Protocol: WireGuard',
                excludeSemantics: true,
                child: Text('WireGuard', style: AppTheme.smallBody),
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [location, const SizedBox(height: 8), protocol],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: location),
                        const SizedBox(width: 24),
                        protocol,
                      ],
                    );
            }),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            TransferSummary(
              download: download,
              upload: upload,
              available: countersAvailable,
              label: sessionLabel,
            ),
            if (recordingNotice != null) ...[
              const SizedBox(height: 12),
              Text(recordingNotice!, style: AppTheme.caption),
            ],
            if (monthlyUsage != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              monthlyUsage!,
            ],
          ],
        ),
      );
}

/// Animation/focus state only. No service operations or completion timers.
class _ConnectionControl extends StatefulWidget {
  const _ConnectionControl({
    required this.status,
    required this.action,
    required this.compact,
    required this.disabled,
    required this.onPressed,
  });
  final VpnStatus status;
  final String action;
  final bool compact;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  State<_ConnectionControl> createState() => _ConnectionControlState();
}

class _ConnectionControlState extends State<_ConnectionControl>
    with SingleTickerProviderStateMixin {
  late final _ring =
      AnimationController(vsync: this, duration: AppTheme.ringDuration);
  final _states = WidgetStatesController();
  bool _reduced = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_updateFocus);
  }

  void _updateFocus() {
    final focused = _states.value.contains(WidgetState.focused);
    if (focused == _focused) return;
    void update() {
      if (mounted) setState(() => _focused = focused);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  bool get _transition =>
      widget.status == VpnStatus.connecting ||
      widget.status == VpnStatus.disconnecting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppTheme.reduceMotion(context);
    _syncRing();
  }

  @override
  void didUpdateWidget(covariant _ConnectionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRing();
  }

  void _syncRing() {
    if (_transition && !_reduced) {
      if (!_ring.isAnimating) _ring.repeat();
    } else {
      _ring.stop();
    }
  }

  @override
  void dispose() {
    _states.dispose();
    _ring.dispose();
    super.dispose();
  }

  Color get _hue => switch (widget.status) {
        VpnStatus.connected => AppTheme.connected,
        VpnStatus.error => AppTheme.error,
        VpnStatus.disconnecting => AppTheme.textSecondary,
        _ => AppTheme.accentPrimary,
      };

  Color _surface(Set<WidgetState> states) {
    if (widget.disabled && !_transition) return AppTheme.disabledBackground;
    if (widget.status == VpnStatus.error) {
      if (states.contains(WidgetState.pressed)) {
        return AppTheme.surfaceInteractive;
      }
      if (states.contains(WidgetState.hovered)) return AppTheme.surfaceElevated;
      return AppTheme.surfacePrimary;
    }
    var alpha = switch (widget.status) {
      VpnStatus.disconnected => 0.0,
      VpnStatus.disconnecting => .04,
      _ => .08,
    };
    if (states.contains(WidgetState.pressed)) {
      alpha = widget.status == VpnStatus.disconnected ? .12 : .16;
    } else if (states.contains(WidgetState.hovered)) {
      alpha = widget.status == VpnStatus.disconnected ? .08 : .12;
    }
    return AppTheme.stateSurface(_hue, alpha: alpha);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final scale = scaler.scale(16) / 16;
          final desktop = scale <= 1.5
              ? 180 + (scale - 1).clamp(0, .5) * 120
              : 240 + (scale - 1.5).clamp(0, .5) * 80;
          final desired = desktop - (widget.compact ? 20 : 0);
          final diameter =
              math.min(desired, constraints.maxWidth - 12).toDouble();
          final style = AppTheme.button;
          // Match native button content constraints without shrinking text.
          final painter = TextPainter(
              text: TextSpan(text: 'Disconnecting', style: style),
              textDirection: Directionality.of(context),
              textScaler: scaler)
            ..layout();
          final contentHeight = 32 + 12 + painter.height;
          final fits =
              painter.width <= diameter - 40 && contentHeight <= diameter - 40;
          painter.dispose();
          final icon = _transition && _reduced
              ? Icons.hourglass_empty
              : widget.status == VpnStatus.error && widget.action == 'Try again'
                  ? Icons.refresh
                  : Icons.power_settings_new;
          final circle = SizedBox.square(
            dimension: diameter,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: TextButton(
                  key: const ValueKey('connection-action'),
                  statesController: _states,
                  onPressed: widget.disabled ? null : widget.onPressed,
                  style: ButtonStyle(
                    shape: const WidgetStatePropertyAll(CircleBorder()),
                    minimumSize: const WidgetStatePropertyAll(Size.zero),
                    padding: const WidgetStatePropertyAll(EdgeInsets.all(20)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    animationDuration:
                        _reduced ? Duration.zero : AppTheme.interactionDuration,
                    backgroundColor: WidgetStateProperty.resolveWith(_surface),
                    foregroundColor:
                        const WidgetStatePropertyAll(AppTheme.textPrimary),
                    side: WidgetStatePropertyAll(BorderSide(
                        width: 2,
                        color: widget.disabled && !_transition
                            ? AppTheme.borderStrong
                            : _hue)),
                  ),
                  child: Semantics(
                    label: widget.action,
                    excludeSemantics: true,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 32, color: _hue),
                      if (fits) ...[
                        const SizedBox(height: 12),
                        Text(widget.action,
                            textAlign: TextAlign.center, style: style),
                      ],
                    ]),
                  ),
                ),
              ),
              if (_transition && !_reduced)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: diameter - 16,
                      child: AnimatedBuilder(
                        animation: _ring,
                        builder: (context, child) =>
                            CustomPaint(painter: _BusyRing(_hue, _ring.value)),
                      ),
                    ),
                  ),
                ),
            ]),
          );
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    width: 2,
                    color: _focused ? AppTheme.focusRing : Colors.transparent),
              ),
              child: circle,
            ),
            if (!fits) ...[
              const SizedBox(height: 8),
              ExcludeSemantics(
                  child: Text(widget.action,
                      textAlign: TextAlign.center, style: style)),
            ],
          ]);
        },
      );
}

class _BusyRing extends CustomPainter {
  _BusyRing(this.color, this.progress);
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawOval(bounds, paint..color = color.withValues(alpha: .16));
    canvas.drawArc(bounds, progress * math.pi * 2 - math.pi / 2, math.pi / 2,
        false, paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _BusyRing oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}
