import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// SecureWave frosted glass panel with optional accent glow.
///
/// Uses [BackdropFilter] + semi-transparent fill for the glass effect.
/// The [glowColor] param enables a neon BoxShadow ring around the panel.
///
/// Differences from `lib/ui/widgets/glass_panel.dart`:
///   - HTB color tokens (HtbColors) instead of AppColors
///   - Optional [glowColor] + [borderColor] overrides
///   - Optional [glowIntensity] multiplier (0.0–1.0)
///   - Default fill is [HtbColors.glassFill] (dark bg1 @ 80%)
class HtbGlassPanel extends StatelessWidget {
  const HtbGlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
    this.borderColor,
    this.glowColor,
    this.glowIntensity = 1.0,
    this.blurSigma = AppTokens.blurSigma,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry? borderRadius;

  /// Override fill color. Defaults to [HtbColors.glassFill].
  final Color? color;

  /// Override border color. Defaults to [HtbColors.glassBorderDefault].
  final Color? borderColor;

  /// Neon glow color. When non-null, adds a BoxShadow ring with this color.
  final Color? glowColor;

  /// Multiplier for glow opacity (0.0–1.0). Default 1.0 = full.
  final double glowIntensity;

  /// Backdrop blur sigma. Default is [AppTokens.blurSigma] (16).
  final double blurSigma;

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final resolvedRadius =
        borderRadius ?? const BorderRadius.all(Radius.circular(AppTokens.radiusCard));
    final resolvedFill = color ?? HtbColors.glassFill;
    final resolvedBorder = borderColor ?? HtbColors.glassBorderDefault;

    final List<BoxShadow> shadows = glowColor != null
        ? [
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.45 * glowIntensity),
              blurRadius: 24,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.20 * glowIntensity),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ]
        : const [];

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: resolvedRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: resolvedRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            width: width,
            height: height,
            padding:
                padding ?? const EdgeInsets.all(AppTokens.paddingM),
            decoration: BoxDecoration(
              color: resolvedFill,
              borderRadius: resolvedRadius,
              border: Border.all(
                color: resolvedBorder,
                width: AppTokens.borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Convenience variant with the primary accent glow pre-configured.
class NeonGlassPanel extends StatelessWidget {
  const NeonGlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glowIntensity = 0.7,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry? borderRadius;
  final double glowIntensity;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return HtbGlassPanel(
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      borderColor: HtbColors.glassBorderNeon,
      glowColor: HtbColors.accentPrimary,
      glowIntensity: glowIntensity,
      width: width,
      height: height,
      child: child,
    );
  }
}
