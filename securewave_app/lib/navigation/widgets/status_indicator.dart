import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/vpn_ui_bindings.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_spacing.dart';

/// Status indicator — v2.
///
/// Pulsing dot with optional label.
/// When busy (connecting/disconnecting) the dot scales in/out.
/// When connected it shows a steady green glow.
class StatusIndicator extends ConsumerStatefulWidget {
  const StatusIndicator({super.key, this.showLabel = false});
  final bool showLabel;

  @override
  ConsumerState<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends ConsumerState<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visualState = ref.watch(connectionVisualStateProvider);
    final color = _color(visualState);
    final statusText = widget.showLabel ? _label(visualState) : null;
    final isBusy = visualState == ConnectionVisualState.connecting ||
        visualState == ConnectionVisualState.reconnecting ||
        visualState == ConnectionVisualState.disconnecting;

    if (isBusy && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!isBusy && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Status dot ───────────────────────────────────────────────
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, _) {
              final scale = isBusy ? _pulseAnim.value : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 7,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ── Label ────────────────────────────────────────────────────
        if (widget.showLabel) ...[
          const SizedBox(width: AppSpacing.space2),
          AnimatedSwitcher(
            duration: AppAnimations.durationFast,
            child: Text(
              statusText ?? '',
              key: ValueKey(visualState),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  Color _color(ConnectionVisualState state) => switch (state) {
        ConnectionVisualState.connected => const Color(0xFF2E7D32),
        ConnectionVisualState.connecting => const Color(0xFF0277BD),
        ConnectionVisualState.reconnecting => const Color(0xFFF57C00),
        ConnectionVisualState.disconnecting => const Color(0xFF546E7A),
        ConnectionVisualState.error => const Color(0xFFC62828),
        ConnectionVisualState.disconnected => const Color(0xFF607D8B),
      };

  String _label(ConnectionVisualState state) => switch (state) {
        ConnectionVisualState.connected => 'Connected',
        ConnectionVisualState.connecting => 'Connecting',
        ConnectionVisualState.reconnecting => 'Reconnecting',
        ConnectionVisualState.disconnecting => 'Disconnecting',
        ConnectionVisualState.error => 'Error',
        ConnectionVisualState.disconnected => 'Disconnected',
      };
}
