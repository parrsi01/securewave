import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_spacing.dart';

class StatusIndicator extends ConsumerStatefulWidget {
  const StatusIndicator({super.key, this.showLabel = false});
  final bool showLabel;

  @override
  ConsumerState<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends ConsumerState<StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    final isBusy = vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.disconnecting;

    if (isBusy && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!isBusy && _pulseController.isAnimating) {
      _pulseController.forward().then((_) => _pulseController.reset());
    }

    final color = vpnState.statusColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = isBusy ? 0.8 + 0.4 * _pulseController.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (widget.showLabel) ...[
          const SizedBox(width: AppSpacing.space2),
          AnimatedSwitcher(
            duration: AppAnimations.durationFast,
            child: Text(
              vpnState.statusText(),
              key: ValueKey(vpnState.status),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
