import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../theme/securewave_palette.dart';

class ConnectionRing extends ConsumerStatefulWidget {
  const ConnectionRing({super.key});

  @override
  ConsumerState<ConnectionRing> createState() => _ConnectionRingState();
}

class _ConnectionRingState extends ConsumerState<ConnectionRing>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1,
      value: 1,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);
    final status = vpn.status;
    final servers = ref.watch(serversProvider);
    final selectedServerId = vpn.selectedServerId;
    final allRegionsDown = servers.maybeWhen(
      data: (items) =>
          items.isNotEmpty &&
          items.every(
            (item) =>
                (item.regionHealthStatus ?? '').trim().toLowerCase() == 'down',
          ),
      orElse: () => false,
    );
    final selectedRegionDown = servers.maybeWhen(
      data: (items) {
        if (selectedServerId == null || selectedServerId.isEmpty) return false;
        for (final item in items) {
          if (item.id != selectedServerId) continue;
          return (item.regionHealthStatus ?? '').trim().toLowerCase() == 'down';
        }
        return false;
      },
      orElse: () => false,
    );
    final busy =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;
    final blocked =
        (status == VpnStatus.disconnected || status == VpnStatus.error) &&
            allRegionsDown;
    final selectedDownBlocked =
        (status == VpnStatus.disconnected || status == VpnStatus.error) &&
            selectedRegionDown;

    final (label, icon, accent) = switch (status) {
      VpnStatus.connected => (
          'Protected',
          Icons.check_rounded,
          SecureWavePalette.success,
        ),
      VpnStatus.connecting => (
          'Working',
          Icons.sync_rounded,
          SecureWavePalette.warning,
        ),
      VpnStatus.disconnecting => (
          'Pausing',
          Icons.sync_rounded,
          SecureWavePalette.warning,
        ),
      VpnStatus.error => (
          'Error',
          Icons.warning_amber_rounded,
          SecureWavePalette.danger,
        ),
      VpnStatus.disconnected => (
          'Connect',
          Icons.shield_outlined,
          SecureWavePalette.brand,
        ),
    };

    return Semantics(
      key: const ValueKey<String>(AutomationKeys.connectionRingButton),
      button: true,
      enabled: !busy && !blocked && !selectedDownBlocked,
      child: GestureDetector(
        onTapDown: busy || blocked || selectedDownBlocked
            ? null
            : (_) => _scaleController.reverse(),
        onTapCancel: busy || blocked || selectedDownBlocked
            ? null
            : () => _scaleController.forward(),
        onTapUp: busy || blocked || selectedDownBlocked
            ? null
            : (_) {
                _scaleController.forward();
                final notifier = ref.read(vpnStateProvider.notifier);
                if (status == VpnStatus.connected) {
                  notifier.disconnect();
                } else {
                  notifier.connect();
                }
              },
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: SizedBox(
            width: 248,
            height: 248,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: <Widget>[
                if (status == VpnStatus.connected)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final value = _pulseController.value;
                      return CustomPaint(
                        painter: _PulsePainter(
                          color: accent,
                          t: value,
                        ),
                      );
                    },
                  ),
                AnimatedBuilder(
                  animation: _rotateController,
                  builder: (context, child) {
                    final rotation = busy ? _rotateController.value : 0.14;
                    return Transform.rotate(
                      angle: rotation * math.pi * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: <Color>[
                              accent.withValues(alpha: 0.2),
                              accent,
                              accent.withValues(alpha: 0.25),
                              accent.withValues(alpha: 0.08),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surface,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: <Color>[
                                          accent.withValues(alpha: 0.18),
                                          accent.withValues(alpha: 0.05),
                                        ],
                                      ),
                                    ),
                                    child: Icon(icon, size: 34, color: accent),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    vpn.statusText(includeEllipsis: true),
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var index = 0; index < 2; index += 1) {
      final progress = ((t + index * 0.5) % 1);
      final radius = 96 + (progress * 42);
      final alpha = (1 - progress) * 0.16;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14 * (1 - progress * 0.55)
        ..color = color.withValues(alpha: alpha.clamp(0, 1));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.color != color;
  }
}
