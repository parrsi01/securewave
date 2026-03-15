import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// SecureWave brand mark — shield icon + text.
///
/// Renders the SecureWave brand as a shield icon with "SecureWave" text.
/// Falls back to icon-only when [showText] is false.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 48,
    this.color,
    this.showText = true,
    this.textSize = 20,
  });

  /// Size of the shield icon.
  final double size;

  /// Optional color override for the icon.
  final Color? color;

  /// Whether to show the "SecureWave" text next to the icon.
  final bool showText;

  /// Font size for the brand text.
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AppColors.primaryBright;

    if (!showText) {
      return Icon(
        Icons.shield_rounded,
        size: size,
        color: iconColor,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shield_rounded,
          size: size,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Secure',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: textSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Wave',
                style: TextStyle(
                  color: iconColor,
                  fontSize: textSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
