import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Central connect/disconnect button with animated states.
///
/// Uses standard [AnimationController] rather than flutter_animate to avoid
/// pending-timer issues in widget tests.
class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.visualState,
    required this.onTap,
  });

  final ConnectionVisualState visualState;
  final VoidCallback onTap;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

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
    if (widget.visualState == ConnectionVisualState.connected) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static const double _size = AppSpacing.connectionRingSize;

  @override
  Widget build(BuildContext context) {
    final gradient = _gradient(widget.visualState);
    final label = _label(widget.visualState);
    final busy = widget.visualState == ConnectionVisualState.connecting ||
        widget.visualState == ConnectionVisualState.disconnecting ||
        widget.visualState == ConnectionVisualState.reconnecting;

    return GestureDetector(
      onTap: busy ? null : widget.onTap,
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Background circle ───────────────────────────────────
              Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
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

              // ── Spinning arc for busy states ────────────────────────
              if (busy)
                SizedBox(
                  width: _size - 20,
                  height: _size - 20,
                  child: const CircularProgressIndicator(
                    strokeWidth: AppSpacing.connectionRingStroke,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white54),
                  ),
                ),

              // ── Label ───────────────────────────────────────────────
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _icon(widget.visualState),
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Gradient _gradient(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F8F5C), Color(0xFF156B44)],
          ),
        ConnectionVisualState.error => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB3261E), Color(0xFF8B1A15)],
          ),
        _ => AppColors.brandGradient,
      };

  Color _glowColor(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => AppColors.success,
        ConnectionVisualState.error => AppColors.error,
        _ => AppColors.primary,
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
        ConnectionVisualState.connecting => 'Connecting…',
        ConnectionVisualState.reconnecting => 'Reconnecting…',
        ConnectionVisualState.disconnecting => 'Disconnecting…',
        ConnectionVisualState.error => 'Error',
        ConnectionVisualState.disconnected => 'Connect',
      };
}
