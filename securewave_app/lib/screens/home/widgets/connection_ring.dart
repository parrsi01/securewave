import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_protocol.dart';
import '../../../core/models/vpn_status.dart';
import '../../../core/state/app_state.dart';
import '../../../core/state/vpn_state.dart';
import '../../../debug/automation_keys.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Connection ring — v2.
///
/// Multi-layer ring with:
/// - Outer decorative ring (always visible, tinted)
/// - Inner interactive ring (status-colored)
/// - Glow pulse rings when connected (concentric expanding circles)
/// - Sweep gradient when connecting/disconnecting
/// - Press-scale spring animation
class ConnectionRing extends ConsumerStatefulWidget {
  const ConnectionRing({super.key});

  @override
  ConsumerState<ConnectionRing> createState() => _ConnectionRingState();
}

class _ConnectionRingState extends ConsumerState<ConnectionRing>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _scaleCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.ringRotationDuration,
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.glowPulseDuration,
    );
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.durationFast,
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: AppAnimations.connectionButtonScale,
    ).animate(CurvedAnimation(
      parent: _scaleCtrl,
      curve: AppAnimations.curveDefault,
    ));
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    _scaleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _syncAnimations(VpnStatus status) {
    switch (status) {
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
        _glowCtrl.reset();
        _pulseCtrl.reset();
      case VpnStatus.connected:
        _rotationCtrl.stop();
        _rotationCtrl.reset();
        if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
        if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat();
      case VpnStatus.disconnected:
      case VpnStatus.error:
        _rotationCtrl.reset();
        _glowCtrl.reset();
        _pulseCtrl.reset();
    }
  }

  Color _statusColor(VpnStatus status, VpnErrorKind? errorKind) {
    final backendUnreachable = status == VpnStatus.error &&
        errorKind == VpnErrorKind.backendUnreachable;
    return switch (status) {
      VpnStatus.connected => AppColors.success,
      VpnStatus.connecting => AppColors.secondary,
      VpnStatus.disconnecting => AppColors.secondary,
      VpnStatus.error =>
        backendUnreachable ? AppColors.error : AppColors.warning,
      VpnStatus.disconnected => AppColors.inkSoft,
    };
  }

  void _onTap(VpnStatus status) {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(vpnStateProvider.notifier);
    if (status == VpnStatus.connected) {
      unawaited(notifier.disconnect());
    } else if (status == VpnStatus.disconnected || status == VpnStatus.error) {
      unawaited(notifier.connect());
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vpnStateProvider.select((s) => s.status));
    final errorKind = ref.watch(vpnStateProvider.select((s) => s.errorKind));
    final selectedProtocol =
        ref.watch(vpnStateProvider.select((s) => s.protocol));
    final selectedServerId =
        ref.watch(vpnStateProvider.select((s) => s.selectedServerId));
    final effectiveProtocol =
        ref.watch(vpnStateProvider.select((s) => s.effectiveProtocol));
    final statusText =
        ref.watch(vpnStateProvider.select((s) => s.statusText()));
    final servers = ref.watch(serversProvider);
    final allRegionsDown = servers.maybeWhen(
      data: (list) =>
          list.isNotEmpty &&
          list.every((item) =>
              (item.regionHealthStatus ?? '').toLowerCase().trim() == 'down'),
      orElse: () => false,
    );
    final selectedRegionDown = servers.maybeWhen(
      data: (list) {
        if (selectedServerId == null || selectedServerId.isEmpty) return false;
        for (final item in list) {
          if (item.id != selectedServerId) continue;
          return (item.regionHealthStatus ?? '').toLowerCase().trim() == 'down';
        }
        return false;
      },
      orElse: () => false,
    );
    _syncAnimations(status);

    final color = _statusColor(status, errorKind);
    final isBusy =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;
    final isConnected = status == VpnStatus.connected;
    final connectBlocked =
        (status == VpnStatus.disconnected || status == VpnStatus.error) &&
            allRegionsDown;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const size = AppSpacing.connectionRingSize;

    final protocolLabel = () {
      if (selectedProtocol == VpnProtocol.auto && effectiveProtocol == null) {
        return 'Automatic';
      }
      if (selectedProtocol == VpnProtocol.auto && effectiveProtocol != null) {
        return 'Automatic, using ${vpnProtocolLabel(effectiveProtocol)}';
      }
      return vpnProtocolLabel(effectiveProtocol ?? selectedProtocol);
    }();
    final actionHint = connectBlocked
        ? (allRegionsDown
            ? 'No servers available. Connection is disabled.'
            : 'No healthy servers are currently available.')
        : selectedRegionDown
            ? 'Selected region is offline. Connect to fail over to a healthy region automatically.'
            : isBusy
                ? 'VPN action in progress. Please wait.'
                : (status == VpnStatus.connected
                    ? 'Double tap to disconnect.'
                    : 'Double tap to connect.');

    return Semantics(
      key: const ValueKey<String>(AutomationKeys.connectionRingButton),
      button: true,
      enabled: !isBusy && !connectBlocked,
      label:
          'VPN connection button. Status: $statusText. Protocol: $protocolLabel.',
      hint: actionHint,
      child: GestureDetector(
        onTapDown:
            !isBusy && !connectBlocked ? (_) => _scaleCtrl.forward() : null,
        onTapUp: !isBusy && !connectBlocked
            ? (_) {
                _scaleCtrl.reverse();
                _onTap(status);
              }
            : null,
        onTapCancel:
            !isBusy && !connectBlocked ? () => _scaleCtrl.reverse() : null,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Pulse rings when connected ──────────────────────────
                if (isConnected)
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _PulseRingPainter(
                            color: color,
                            progress: _pulseCtrl.value,
                          ),
                        );
                      },
                    ),
                  ),

                // ── Main ring layer ─────────────────────────────────────
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_rotationCtrl, _glowCtrl]),
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _DualRingPainter(
                          color: color,
                          rotation: _rotationCtrl.value * 2 * math.pi,
                          glowIntensity:
                              isConnected ? 0.08 + 0.14 * _glowCtrl.value : 0.0,
                          isBusy: isBusy,
                          isDark: isDark,
                        ),
                      );
                    },
                  ),
                ),

                // ── Center content ──────────────────────────────────────
                Center(
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: AppAnimations.durationNormal,
                      switchInCurve: AppAnimations.curveEnter,
                      switchOutCurve: AppAnimations.curveExit,
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(begin: 0.7, end: 1.0)
                            .animate(CurvedAnimation(
                          parent: anim,
                          curve: AppAnimations.curveEnter,
                        )),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: _centerContent(context, status, color),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerContent(BuildContext context, VpnStatus status, Color color) {
    return switch (status) {
      VpnStatus.disconnected => const _RingCenter(
          key: ValueKey('disconnected'),
          icon: Icons.shield_outlined,
          label: 'Connect',
          color: AppColors.primary,
          showSpinner: false,
        ),
      VpnStatus.connecting => const _RingCenter(
          key: ValueKey('connecting'),
          icon: null,
          label: 'Connecting',
          color: AppColors.secondary,
          showSpinner: true,
        ),
      VpnStatus.connected => const _RingCenter(
          key: ValueKey('connected'),
          icon: Icons.check_rounded,
          label: 'Protected',
          color: AppColors.success,
          showSpinner: false,
        ),
      VpnStatus.disconnecting => const _RingCenter(
          key: ValueKey('disconnecting'),
          icon: null,
          label: 'Disconnecting',
          color: AppColors.secondary,
          showSpinner: true,
        ),
      VpnStatus.error => const _RingCenter(
          key: ValueKey('error'),
          icon: Icons.warning_amber_rounded,
          label: 'Error',
          color: AppColors.error,
          showSpinner: false,
        ),
    };
  }
}

// ── Center content widget ──────────────────────────────────────────────────

class _RingCenter extends StatelessWidget {
  const _RingCenter({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.showSpinner,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpinner)
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          )
        else
          Icon(icon, size: 44, color: color),
        const SizedBox(height: AppSpacing.space2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Dual Ring Painter ──────────────────────────────────────────────────────

class _DualRingPainter extends CustomPainter {
  _DualRingPainter({
    required this.color,
    required this.rotation,
    required this.glowIntensity,
    required this.isBusy,
    required this.isDark,
  });

  final Color color;
  final double rotation;
  final double glowIntensity;
  final bool isBusy;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 6;
    final innerR = size.width / 2 - 18;

    // ── Glow bloom ─────────────────────────────────────────────────────
    if (glowIntensity > 0) {
      canvas.drawCircle(
        center,
        outerR + 18,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: glowIntensity),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: outerR + 18)),
      );
    }

    // ── Outer decorative ring (always visible, muted) ───────────────────
    final outerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: isDark ? 0.20 : 0.14);
    canvas.drawCircle(center, outerR, outerRingPaint);

    // ── Inner interactive ring (status-colored) ─────────────────────────
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppSpacing.connectionRingStroke
      ..strokeCap = StrokeCap.round;

    if (isBusy) {
      // Sweep gradient for connecting/disconnecting state
      innerPaint.shader = SweepGradient(
        colors: [color, color.withValues(alpha: 0.15), color],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(rotation),
      ).createShader(Rect.fromCircle(center: center, radius: innerR));
    } else {
      innerPaint.color = color;
    }
    canvas.drawCircle(center, innerR, innerPaint);

    // ── Inner fill circle (glass-like center zone) ──────────────────────
    final fillR = innerR - AppSpacing.connectionRingStroke / 2 - 2;
    canvas.drawCircle(
      center,
      fillR,
      Paint()
        ..color = isDark
            ? AppColors.darkSurface.withValues(alpha: 0.85)
            : AppColors.surface.withValues(alpha: 0.90),
    );
  }

  @override
  bool shouldRepaint(_DualRingPainter old) =>
      color != old.color ||
      rotation != old.rotation ||
      glowIntensity != old.glowIntensity ||
      isBusy != old.isBusy ||
      isDark != old.isDark;
}

// ── Pulse Ring Painter (expanding rings when connected) ───────────────────

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({required this.color, required this.progress});
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width / 2 - 18;

    for (int i = 0; i < 2; i++) {
      final t = ((progress + i * 0.5) % 1.0);
      final radius = baseR + t * 32;
      final alpha = (1.0 - t) * 0.18;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) =>
      color != old.color || progress != old.progress;
}
