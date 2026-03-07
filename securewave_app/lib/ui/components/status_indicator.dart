import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Small dot + label showing VPN visual state.
class StatusIndicator extends StatefulWidget {
  const StatusIndicator({super.key, required this.visualState});

  final ConnectionVisualState visualState;

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 1, end: 1.4).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(StatusIndicator old) {
    super.didUpdateWidget(old);
    if (old.visualState != widget.visualState) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    final pulse = widget.visualState == ConnectionVisualState.connecting ||
        widget.visualState == ConnectionVisualState.reconnecting;
    if (pulse) {
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

  @override
  Widget build(BuildContext context) {
    final color = _color(widget.visualState);
    final label = _label(widget.visualState);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _scale,
          builder: (_, __) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Color _color(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => AppColors.success,
        ConnectionVisualState.connecting => AppColors.secondary,
        ConnectionVisualState.reconnecting => AppColors.warning,
        ConnectionVisualState.disconnecting => AppColors.inkSoft,
        ConnectionVisualState.error => AppColors.error,
        ConnectionVisualState.disconnected => AppColors.inkSoft,
      };

  String _label(ConnectionVisualState s) => switch (s) {
        ConnectionVisualState.connected => 'Connected',
        ConnectionVisualState.connecting => 'Connecting',
        ConnectionVisualState.reconnecting => 'Reconnecting',
        ConnectionVisualState.disconnecting => 'Disconnecting',
        ConnectionVisualState.error => 'Error',
        ConnectionVisualState.disconnected => 'Disconnected',
      };
}
