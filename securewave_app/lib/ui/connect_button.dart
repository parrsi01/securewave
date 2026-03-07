import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/models/vpn_status.dart';
import 'app_ui_v1.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.status,
    required this.isBusy,
    required this.onPressed,
  });

  final VpnStatus status;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isConnected = status == VpnStatus.connected;
    final label = switch (status) {
      VpnStatus.connected => 'Disconnect',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.error => 'Retry',
      VpnStatus.disconnected => 'Quick Connect',
    };

    final glowColor = isConnected ? AppUIv1.success : AppUIv1.accent;

    return GestureDetector(
      onTap: isBusy ? null : onPressed,
      child: AnimatedContainer(
        duration: 300.ms,
        width: 196,
        height: 196,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              glowColor.withValues(alpha: 0.25),
              glowColor.withValues(alpha: 0.1),
              AppUIv1.surface,
            ],
          ),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.25),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isConnected ? Icons.power_settings_new : Icons.shield_outlined,
                color: AppUIv1.ink,
                size: 44,
              ),
              const SizedBox(height: AppUIv1.space2),
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppUIv1.space1),
              Text(
                isConnected ? 'Protected' : 'Tap to secure this device',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ).animate(
        onPlay: (controller) {
          if (status == VpnStatus.connecting ||
              status == VpnStatus.reconnecting) {
            controller.repeat(reverse: true);
          }
        },
      ).scale(
        begin: const Offset(0.98, 0.98),
        end: const Offset(1.02, 1.02),
        duration: 900.ms,
      ),
    );
  }
}
