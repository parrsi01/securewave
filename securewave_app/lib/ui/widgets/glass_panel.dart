import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Frosted glass card with backdrop blur.
///
/// Adapts fill & border colors to current brightness using AppColors
/// glassmorphism tokens.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.color,
    this.borderColor,
    this.glowColor,
    this.gradient,
    this.blurSigma = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;

  /// Override the fill color. When null, uses AppColors.glassFillDark/Light
  /// based on the ambient brightness.
  final Color? color;
  final Color? borderColor;
  final Color? glowColor;
  final Gradient? gradient;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor =
        color ?? (isDark ? AppColors.glassFillDark : AppColors.glassFillLight);
    final resolvedBorderColor = borderColor ??
        (isDark ? AppColors.glassBorderDark : AppColors.glassBorderLight);
    final radius = borderRadius ?? BorderRadius.circular(AppSpacing.radiusL);
    final shadowColor = glowColor ??
        (isDark
            ? AppColors.primaryBright
            : Colors.black.withValues(alpha: 0.1));

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            gradient: gradient,
            borderRadius: radius,
            border: Border.all(color: resolvedBorderColor, width: 1),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: shadowColor.withValues(
                        alpha: glowColor == null ? 0.18 : 0.22,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                    if (glowColor != null)
                      BoxShadow(
                        color: glowColor!.withValues(alpha: 0.14),
                        blurRadius: 44,
                        spreadRadius: -6,
                      ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 12),
                    ),
                  ],
          ),
          padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
          child: child,
        ),
      ),
    );
  }
}
