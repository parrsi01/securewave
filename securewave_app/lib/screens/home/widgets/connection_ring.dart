import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class ConnectionRing extends ConsumerStatefulWidget {
  const ConnectionRing({super.key});

  @override
  ConsumerState<ConnectionRing> createState() => _ConnectionRingState();
}

class _ConnectionRingState extends ConsumerState<ConnectionRing>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _glowController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: AppAnimations.glowPulseDuration,
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: AppAnimations.durationFast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: AppAnimations.connectionButtonScale,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: AppAnimations.curveDefault,
    ));
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _glowController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _syncAnimations(VpnStatus status) {
    switch (status) {
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        if (!_rotationController.isAnimating) _rotationController.repeat();
        _glowController.reset();
      case VpnStatus.connected:
        _rotationController.reset();
        if (!_glowController.isAnimating) _glowController.repeat(reverse: true);
      case VpnStatus.disconnected:
      case VpnStatus.error:
        _rotationController.reset();
        _glowController.reset();
    }
  }

  void _onTap(VpnState state) {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(vpnStateProvider.notifier);
    if (state.status == VpnStatus.connected) {
      notifier.disconnect();
    } else if (state.status == VpnStatus.disconnected ||
        state.status == VpnStatus.error) {
      notifier.connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    _syncAnimations(vpnState.status);

    final color = vpnState.statusColor;
    final isBusy = vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.disconnecting;

    return Semantics(
      button: true,
      label: 'VPN connection. Status: ${vpnState.statusText()}.',
      child: GestureDetector(
        onTapDown: !isBusy ? (_) => _scaleController.forward() : null,
        onTapUp: !isBusy
            ? (_) {
                _scaleController.reverse();
                _onTap(vpnState);
              }
            : null,
        onTapCancel: !isBusy ? () => _scaleController.reverse() : null,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: SizedBox(
            width: 200,
            height: 200,
            child: AnimatedBuilder(
              animation: Listenable.merge([_rotationController, _glowController]),
              builder: (context, child) {
                return CustomPaint(
                  painter: _RingPainter(
                    color: color,
                    rotation: _rotationController.value * 2 * math.pi,
                    glow: vpnState.status == VpnStatus.connected
                        ? 0.12 + 0.18 * _glowController.value
                        : 0.0,
                    isBusy: isBusy,
                  ),
                  child: child,
                );
              },
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppAnimations.durationNormal,
                  switchInCurve: AppAnimations.curveEnter,
                  switchOutCurve: AppAnimations.curveExit,
                  child: _centerContent(vpnState),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerContent(VpnState s) {
    final (IconData? icon, String label, Color c, bool spinner) = switch (s.status) {
      VpnStatus.disconnected => (Icons.shield_outlined, 'Tap to Connect', AppColors.primary, false),
      VpnStatus.connecting => (null, 'Connecting', AppColors.secondary, true),
      VpnStatus.connected => (Icons.check_rounded, 'Connected', AppColors.success, false),
      VpnStatus.disconnecting => (null, 'Disconnecting', AppColors.secondary, true),
      VpnStatus.error => (Icons.warning_amber_rounded, 'Retry', AppColors.error, false),
    };

    return Column(
      key: ValueKey(s.status),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spinner)
          SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: c))
        else
          Icon(icon, size: 40, color: c),
        const SizedBox(height: AppSpacing.space2),
        Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.rotation, required this.glow, required this.isBusy});
  final Color color;
  final double rotation;
  final double glow;
  final bool isBusy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius + 20,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: glow), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius + 20)),
      );
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    if (isBusy) {
      ring.shader = SweepGradient(
        colors: [color, color.withValues(alpha: 0.2), color],
        stops: const [0, 0.5, 1],
        transform: GradientRotation(rotation),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      ring.color = color;
    }
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      color != old.color || rotation != old.rotation || glow != old.glow || isBusy != old.isBusy;
}
