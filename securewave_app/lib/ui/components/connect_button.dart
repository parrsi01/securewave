import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/models/vpn_status.dart';
import '../design_tokens.dart';
import '../theme/breakpoints.dart';

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
    final breakpoint = SecureWaveBreakpoints.of(context);
    final size = switch (breakpoint) {
      SecureWaveBreakpoint.mobile => 160.0,
      SecureWaveBreakpoint.tablet => 200.0,
      SecureWaveBreakpoint.desktop => 220.0,
    };
    final glowColor = switch (status) {
      VpnStatus.connected => SecureWaveTokens.success,
      VpnStatus.connecting => SecureWaveTokens.accentSun,
      VpnStatus.reconnecting => SecureWaveTokens.accentSun,
      VpnStatus.disconnecting => SecureWaveTokens.warning,
      VpnStatus.error => SecureWaveTokens.danger,
      VpnStatus.disconnected => SecureWaveTokens.accent,
    };
    final title = switch (status) {
      VpnStatus.connected => 'Disconnect',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Retry',
      VpnStatus.disconnected => 'Connect',
    };
    final subtitle = switch (status) {
      VpnStatus.connected => 'Protected',
      VpnStatus.connecting => 'Securing tunnel',
      VpnStatus.reconnecting => 'Recovering connection',
      VpnStatus.disconnecting => 'Releasing tunnel',
      VpnStatus.error => 'Tap to recover',
      VpnStatus.disconnected => 'Tap to secure this device',
    };

    return GestureDetector(
      onTap: isBusy ? null : onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + 36,
            height: size + 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(
                      alpha: status == VpnStatus.connected ? 0.38 : 0.18),
                  blurRadius: status == VpnStatus.connected ? 42 : 28,
                  spreadRadius: status == VpnStatus.connected ? 8 : 1,
                ),
              ],
            ),
          ).animate(
            onPlay: (controller) {
              if (status == VpnStatus.disconnected) {
                controller.repeat(reverse: true);
              }
            },
          ).scaleXY(
            begin: 0.96,
            end: 1.02,
            duration: SecureWaveTokens.animationSlow,
          ),
          AnimatedContainer(
            duration: SecureWaveTokens.animationMedium,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  glowColor.withValues(alpha: 0.9),
                  SecureWaveTokens.backgroundStrong,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Center(
              child: PageTransitionSwitcher(
                duration: SecureWaveTokens.animationMedium,
                transitionBuilder: (child, primary, secondary) =>
                    FadeScaleTransition(
                  animation: primary,
                  child: child,
                ),
                child: isBusy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Column(
                        key: ValueKey<String>(title),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == VpnStatus.connected
                                ? Icons.shield_rounded
                                : Icons.power_settings_new_rounded,
                            size: size * 0.22,
                            color: SecureWaveTokens.ink,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: SecureWaveTokens.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: SecureWaveTokens.inkMuted),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
