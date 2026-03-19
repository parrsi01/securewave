import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../../debug/automation_keys.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Central connect/disconnect button with animated states.
///
/// Uses standard [AnimationController] rather than flutter_animate to avoid
/// pending-timer issues in widget tests.
///
/// Animations:
/// - **Pulse**: gentle scale 1→1.04 when connected (breathing effect).
/// - **Spin**: 120° arc rotation when busy (connecting/disconnecting/reconnecting).
/// - **Crossfade**: icon + label smoothly transition between states.
/// - **Glow**: box shadow color animates via [AnimatedContainer].
class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.visualState,
    required this.onTap,
    this.connectPhaseLabel,
  });

  final ConnectionVisualState visualState;
  final VoidCallback onTap;

  /// Optional sub-phase label shown during [ConnectionVisualState.connecting].
  final String? connectPhaseLabel;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scale = Tween<double>(begin: 1, end: 1.04).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    if (old.visualState != widget.visualState) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (kDebugMode) {
      final enabled = !_isBusy(widget.visualState);
      final reason =
          enabled ? 'ready_for_user_action' : 'transition_in_progress';
      AppLogger.debug(
        '[VPN_UI] {"event":"connect_button_interaction_state","visual_state":"${widget.visualState.name}","enabled":$enabled,"reason":"$reason"}',
        tag: 'SecureWave.UI',
      );
    }
    if (widget.visualState == ConnectionVisualState.connected) {
      _pulse.repeat(reverse: true);
      _spin.stop();
      _spin.value = 0;
    } else if (_isBusy(widget.visualState)) {
      _pulse.stop();
      _pulse.value = 0;
      _spin.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
      _spin.stop();
      _spin.value = 0;
    }
  }

  static bool _isBusy(ConnectionVisualState s) =>
      s == ConnectionVisualState.connecting ||
      s == ConnectionVisualState.disconnecting ||
      s == ConnectionVisualState.reconnecting;

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  static const double _size = AppSpacing.connectionRingSize;

  @override
  Widget build(BuildContext context) {
    final busy = _isBusy(widget.visualState);

    return Semantics(
      button: true,
      label: _label(widget.visualState),
      enabled: !busy,
      child: SizedBox(
        width: _size,
        height: _size,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) {
            return Transform.scale(
              scale: _scale.value,
              child: child,
            );
          },
          child: GestureDetector(
            key: AutomationKeys.connectionRingButtonKey,
            onTap: busy ? null : widget.onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // ── Animated background + glow ────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _gradient(widget.visualState),
                    boxShadow: [
                      BoxShadow(
                        color: _glowColor(widget.visualState)
                            .withValues(alpha: 0.35),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

                // ── Outer ring ────────────────────────────────────────────
                Container(
                  width: _size - 8,
                  height: _size - 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                ),

                // ── Spinning arc for busy states ──────────────────────────
                if (busy)
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (_, __) => Transform.rotate(
                      angle: _spin.value * 2 * math.pi,
                      child: SizedBox(
                        width: _size - 20,
                        height: _size - 20,
                        child: CustomPaint(
                          painter: _ArcPainter(
                            color: Colors.white.withValues(alpha: 0.6),
                            strokeWidth: AppSpacing.connectionRingStroke,
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Icon + label with crossfade ───────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: AutomationKeys.connectionStateKey(
                      widget.visualState.name,
                    ),
                    child: Column(
                      key: ValueKey(
                        '${widget.visualState}_${widget.connectPhaseLabel}',
                      ),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icon(widget.visualState),
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _label(widget.visualState),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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

  Gradient _gradient(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => AppColors.connectedGradient,
        ConnectionVisualState.error => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF5252), Color(0xFFB3261E)],
          ),
        _ => AppColors.brandGradient,
      };

  Color _glowColor(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => AppColors.success,
        ConnectionVisualState.error => AppColors.error,
        _ => AppColors.primaryBright,
      };

  IconData _icon(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => Icons.check_rounded,
        ConnectionVisualState.error => Icons.warning_amber_rounded,
        ConnectionVisualState.connecting => Icons.hourglass_top_rounded,
        ConnectionVisualState.reconnecting => Icons.refresh_rounded,
        ConnectionVisualState.disconnecting => Icons.hourglass_bottom_rounded,
        ConnectionVisualState.disconnected => Icons.shield_outlined,
      };

  String _label(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => 'Protected',
        ConnectionVisualState.connecting =>
          widget.connectPhaseLabel ?? 'Connecting…',
        ConnectionVisualState.reconnecting => 'Reconnecting…',
        ConnectionVisualState.disconnecting => 'Disconnecting…',
        ConnectionVisualState.error => 'Error',
        ConnectionVisualState.disconnected => 'Connect',
      };
}

/// Draws a 120° arc for the busy spinner.
class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi / 3, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
