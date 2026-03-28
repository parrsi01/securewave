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
    final isPulsing = status == VpnStatus.connecting ||
        status == VpnStatus.reconnecting ||
        status == VpnStatus.verifying;
    final label = switch (status) {
      VpnStatus.connected => 'Disconnect',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.verifying => 'Verifying',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.degraded => 'Degraded',
      VpnStatus.error => 'Retry',
      VpnStatus.disconnected => 'Quick Connect',
    };

    final glowColor = isConnected ? AppUIv1.success : AppUIv1.accent;
    final shadows = switch (status) {
      VpnStatus.connecting || VpnStatus.reconnecting || VpnStatus.verifying => [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.18),
            blurRadius: 22,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      VpnStatus.connected => [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.12),
            blurRadius: 16,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      _ => [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
    };

    return GestureDetector(
      onTap: isBusy ? null : onPressed,
      child: AnimatedContainer(
        duration: 300.ms,
        width: 188,
        height: 188,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppUIv1.surface,
          border: Border.all(
            color: glowColor.withValues(alpha: isConnected ? 0.34 : 0.24),
            width: 1.5,
          ),
          boxShadow: shadows,
        ),
        child: Center(
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppUIv1.backgroundStrong,
              border: Border.all(
                color: glowColor.withValues(alpha: isPulsing ? 0.34 : 0.18),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected
                      ? Icons.power_settings_new
                      : Icons.shield_outlined,
                  color: AppUIv1.ink,
                  size: 40,
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
        ),
      ).animate(
        onPlay: (controller) {
          if (isPulsing) {
            controller.repeat(reverse: true);
          }
        },
      ).scale(
        begin: const Offset(0.98, 0.98),
        end: isPulsing ? const Offset(1.01, 1.01) : const Offset(1, 1),
        duration: 900.ms,
      ),
    );
  }
}
