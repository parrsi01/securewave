import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';

class ConnectionButton extends ConsumerStatefulWidget {
  const ConnectionButton({super.key});

  @override
  ConsumerState<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends ConsumerState<ConnectionButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: AppAnimations.glowPulseDuration,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);
    final notifier = ref.read(vpnStateProvider.notifier);

    // Manage glow animation based on connection state
    if (vpn.status == VpnStatus.connected && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (vpn.status != VpnStatus.connected &&
        _glowController.isAnimating) {
      _glowController.stop();
      _glowController.reset();
    }

    final Color bgColor;
    final IconData icon;
    final String label;
    final bool showSpinner;

    switch (vpn.status) {
      case VpnStatus.disconnected:
        bgColor = AppColors.primary;
        icon = Icons.shield_outlined;
        label = 'Connect';
        showSpinner = false;
      case VpnStatus.connecting:
        bgColor = AppColors.secondary;
        icon = Icons.shield_outlined;
        label = 'Connecting...';
        showSpinner = true;
      case VpnStatus.connected:
        bgColor = AppColors.success;
        icon = Icons.check;
        label = 'Disconnect';
        showSpinner = false;
      case VpnStatus.disconnecting:
        bgColor = AppColors.secondary;
        icon = Icons.shield_outlined;
        label = 'Disconnecting...';
        showSpinner = true;
      case VpnStatus.error:
        bgColor = AppColors.error;
        icon = Icons.warning_amber_rounded;
        label = 'Retry';
        showSpinner = false;
    }

    return GestureDetector(
      onTapDown: vpn.isBusy ? null : (_) => setState(() => _pressed = true),
      onTapUp: vpn.isBusy
          ? null
          : (_) {
              setState(() => _pressed = false);
              _onTap(vpn.status, notifier);
            },
      onTapCancel:
          vpn.isBusy ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? AppAnimations.connectionButtonScale : 1.0,
        duration: AppAnimations.durationFast,
        curve: AppAnimations.curveDefault,
        child: AnimatedOpacity(
          opacity: vpn.isBusy ? 0.75 : 1.0,
          duration: AppAnimations.durationFast,
          child: SizedBox(
            width: 180,
            height: 180,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                final glowOpacity = vpn.status == VpnStatus.connected
                    ? 0.12 + (_glowController.value * 0.18)
                    : 0.0;
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: vpn.status == VpnStatus.connected
                        ? [
                            BoxShadow(
                              color: AppColors.success
                                  .withValues(alpha: glowOpacity),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                  child: child,
                );
              },
              child: AnimatedContainer(
                duration: AppAnimations.connectionTransition,
                curve: AppAnimations.curveDefault,
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: bgColor.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: AppAnimations.durationFast,
                        switchInCurve: AppAnimations.curveEnter,
                        switchOutCurve: AppAnimations.curveExit,
                        child: showSpinner
                            ? SizedBox(
                                key: const ValueKey('spinner'),
                                width: 32,
                                height: 32,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Icon(icon,
                                key: ValueKey(icon),
                                size: 40,
                                color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: AppAnimations.durationFast,
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(VpnStatus status, VpnStateNotifier notifier) {
    HapticFeedback.mediumImpact();
    if (status == VpnStatus.connected) {
      notifier.disconnect();
    } else {
      notifier.connect();
    }
  }
}
