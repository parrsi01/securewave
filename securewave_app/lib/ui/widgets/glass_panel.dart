import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;

/// Shared elevated panel surface.
///
/// Keeps cards on flat dark surfaces with restrained borders so only buttons
/// and interactive states carry accent glow.
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
    final fillColor = color ?? (isDark ? htb.HtbColors.bg1 : AppColors.surface);
    final resolvedBorderColor =
        borderColor ?? (isDark ? htb.HtbColors.border : AppColors.border);
    final radius = borderRadius ?? BorderRadius.circular(AppSpacing.radiusL);
    final activeBorderColor = glowColor == null
        ? resolvedBorderColor
        : glowColor!.withValues(alpha: 0.22);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: activeBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );
  }
}
