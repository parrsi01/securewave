import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SecureWaveTypography {
  const SecureWaveTypography._();

  static TextTheme textTheme(Brightness brightness) {
    GoogleFonts.config.allowRuntimeFetching = false;

    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.3),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
