import 'package:flutter/material.dart';

import 'app_colors.dart';

/// SecureWave typography for the dark app theme.
class AppTypography {
  AppTypography._();

  static const String _sansFamily = 'Manrope';
  static const String _monoFamily = 'JetBrainsMono';

  static TextStyle _sans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: _sansFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: _monoFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: _sans(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -1.2,
        height: 1.08,
      ),
      displayMedium: _sans(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.9,
        height: 1.12,
      ),
      displaySmall: _sans(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.18,
      ),
      headlineLarge: _sans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.6,
        height: 1.2,
      ),
      headlineMedium: _sans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.4,
        height: 1.24,
      ),
      headlineSmall: _sans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.28,
      ),
      titleLarge: _sans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.28,
      ),
      titleMedium: _sans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.05,
        height: 1.50,
      ),
      titleSmall: _sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.43,
      ),
      bodyLarge: _sans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.50,
      ),
      bodyMedium: _sans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.5,
      ),
      bodySmall: _sans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: HtbColors.textSecondary,
        letterSpacing: 0.1,
        height: 1.45,
      ),
      labelLarge: _sans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: 0.15,
        height: 1.43,
      ),
      labelMedium: _sans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: HtbColors.textSecondary,
        letterSpacing: 0.2,
        height: 1.33,
      ),
      labelSmall: _sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: HtbColors.textTertiary,
        letterSpacing: 0.2,
        height: 1.45,
      ),
    );
  }

  static TextStyle monoLarge = _mono(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: HtbColors.textMono,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static TextStyle monoMedium = _mono(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: HtbColors.textMono,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static TextStyle monoSmall = _mono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: HtbColors.textSecondary,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static TextStyle monoLabel = _mono(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: HtbColors.textTertiary,
    letterSpacing: 0.3,
    height: 1.5,
  );

  static TextStyle monoNeon = _mono(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: HtbColors.accentPrimary,
    letterSpacing: 0.5,
    height: 1.4,
  );

  static TextStyle monoFallback({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: _monoFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? HtbColors.textMono,
      letterSpacing: 0.3,
    );
  }
}
