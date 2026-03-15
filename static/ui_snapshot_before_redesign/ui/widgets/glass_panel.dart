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
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;

  /// Override the fill color. When null, uses AppColors.glassFillDark/Light
  /// based on the ambient brightness.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = color ?? (isDark ? AppColors.glassFillDark : AppColors.glassFillLight);
    final borderColor = isDark ? AppColors.glassBorderDark : AppColors.glassBorderLight;
    final radius = borderRadius ?? BorderRadius.circular(AppSpacing.radiusL);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: radius,
            border: Border.all(color: borderColor, width: 1),
          ),
          padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
          child: child,
        ),
      ),
    );
  }
}
