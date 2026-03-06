import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../debug/automation_keys.dart';
import '../theme/securewave_theme.dart';
import '../widgets/vpn_ui_bindings.dart';
import 'status_indicator.dart';

class ConnectButton extends StatelessWidget {
  const ConnectButton({
    super.key,
    required this.visualState,
    required this.headline,
    required this.caption,
    required this.onPressed,
    this.diameter = 304,
  });

  final ConnectionVisualState visualState;
  final String headline;
  final String caption;
  final VoidCallback? onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colors = context.swColors;
    final accent = switch (visualState) {
      ConnectionVisualState.connected => colors.connectionActive,
      ConnectionVisualState.error => colors.connectionError,
      ConnectionVisualState.disconnected => colors.connectionInactive,
      _ => colors.primary,
    };
    final gradient = switch (visualState) {
      ConnectionVisualState.connected => context.swGradients.active,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        context.swGradients.accent,
      ConnectionVisualState.error => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFF8C83), Color(0xFF7E2E2C)],
        ),
      ConnectionVisualState.disconnected => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF11303A), Color(0xFF0D2028)],
        ),
    };
    final icon = switch (visualState) {
      ConnectionVisualState.connected => Icons.power_settings_new_rounded,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        Icons.sync_rounded,
      ConnectionVisualState.error => Icons.refresh_rounded,
      ConnectionVisualState.disconnected => Icons.shield_outlined,
    };
    final pulseDuration = switch (visualState) {
      ConnectionVisualState.connected => 2200.ms,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        1300.ms,
      ConnectionVisualState.error => 1100.ms,
      ConnectionVisualState.disconnected => 0.ms,
    };
    final haloVisible = visualState != ConnectionVisualState.disconnected;
    final ringSize = diameter * 0.9;
    final innerSize = diameter * 0.74;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Semantics(
      key: const ValueKey<String>(AutomationKeys.connectionRingButton),
      button: true,
      enabled: onPressed != null,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (haloVisible)
              Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(
                    alpha: visualState == ConnectionVisualState.connected
                        ? 0.14
                        : 0.2,
                  ),
                ),
              )
                  .animate(
                    onPlay: pulseDuration == 0.ms
                        ? null
                        : (controller) => controller.repeat(reverse: true),
                  )
                  .scaleXY(
                    begin: 0.94,
                    end: visualState == ConnectionVisualState.connected
                        ? 1.04
                        : 1.08,
                    duration: pulseDuration,
                    curve: Curves.easeInOut,
                  )
                  .fade(
                    begin: 0.08,
                    end: visualState == ConnectionVisualState.connected
                        ? 0.18
                        : 0.28,
                    duration: pulseDuration,
                    curve: Curves.easeInOut,
                  ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: <Color>[
                    accent.withValues(alpha: 0.08),
                    accent.withValues(alpha: 0.48),
                    accent.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SecureWaveSpacing.spaceXS),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: surfaceColor,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onPressed,
                      borderRadius: BorderRadius.circular(999),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: innerSize,
                        height: innerSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: gradient,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.withValues(
                                alpha: visualState == ConnectionVisualState.connected
                                    ? 0.22
                                    : 0.16,
                              ),
                              blurRadius: visualState == ConnectionVisualState.connected
                                  ? 36
                                  : 24,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(SecureWaveSpacing.spaceSM),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(icon, size: 42, color: Colors.white),
                                const SizedBox(height: SecureWaveSpacing.spaceSM),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Text(
                                    headline,
                                    key: ValueKey<String>(headline),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: SecureWaveSpacing.spaceXS),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: SecureWaveSpacing.spaceMD,
                                  ),
                                  child: Text(
                                    caption,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).swCaption?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.88),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
