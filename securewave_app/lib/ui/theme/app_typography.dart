import 'package:flutter/material.dart';

import 'app_colors.dart';

/// SecureWave typography for the dark app theme.
class AppTypography {
  AppTypography._();

  static const String _sansFamily = 'Manrope';
  static const String _monoFamily = 'JetBrainsMono';

  // Shared type scale.
  static const double sizeLabelSmall = 11;
  static const double sizeLabelMedium = 12;
  static const double sizeBodySmall = 13;
  static const double sizeBodyMedium = 14;
  static const double sizeBodyLarge = 16;
  static const double sizeTitleSmall = 16;
  static const double sizeTitleMedium = 18;
  static const double sizeTitleLarge = 20;
  static const double sizeHeadlineSmall = 24;
  static const double sizeHeadlineMedium = 28;
  static const double sizeHeadlineLarge = 32;
  static const double sizeDisplaySmall = 34;
  static const double sizeDisplayMedium = 44;
  static const double sizeDisplayLarge = 56;

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
        fontSize: sizeDisplayLarge,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -1.2,
        height: 1.08,
      ),
      displayMedium: _sans(
        fontSize: sizeDisplayMedium,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.9,
        height: 1.12,
      ),
      displaySmall: _sans(
        fontSize: sizeDisplaySmall,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.18,
      ),
      headlineLarge: _sans(
        fontSize: sizeHeadlineLarge,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.6,
        height: 1.2,
      ),
      headlineMedium: _sans(
        fontSize: sizeHeadlineMedium,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.4,
        height: 1.24,
      ),
      headlineSmall: _sans(
        fontSize: sizeHeadlineSmall,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.28,
      ),
      titleLarge: _sans(
        fontSize: sizeTitleLarge,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: _sans(
        fontSize: sizeTitleMedium,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: -0.05,
        height: 1.33,
      ),
      titleSmall: _sans(
        fontSize: sizeTitleSmall,
        fontWeight: FontWeight.w600,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.38,
      ),
      bodyLarge: _sans(
        fontSize: sizeBodyLarge,
        fontWeight: FontWeight.w400,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.50,
      ),
      bodyMedium: _sans(
        fontSize: sizeBodyMedium,
        fontWeight: FontWeight.w400,
        color: HtbColors.textPrimary,
        letterSpacing: 0,
        height: 1.5,
      ),
      bodySmall: _sans(
        fontSize: sizeBodySmall,
        fontWeight: FontWeight.w400,
        color: HtbColors.textSecondary,
        letterSpacing: 0.05,
        height: 1.5,
      ),
      labelLarge: _sans(
        fontSize: sizeBodyMedium,
        fontWeight: FontWeight.w700,
        color: HtbColors.textPrimary,
        letterSpacing: 0.15,
        height: 1.43,
      ),
      labelMedium: _sans(
        fontSize: sizeLabelMedium,
        fontWeight: FontWeight.w600,
        color: HtbColors.textSecondary,
        letterSpacing: 0.25,
        height: 1.33,
      ),
      labelSmall: _sans(
        fontSize: sizeLabelSmall,
        fontWeight: FontWeight.w600,
        color: HtbColors.textSecondary,
        letterSpacing: 0.35,
        height: 1.45,
      ),
    );
  }

  static TextStyle monoLarge = _mono(
    fontSize: sizeHeadlineSmall,
    fontWeight: FontWeight.w600,
    color: HtbColors.textMono,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static TextStyle monoMedium = _mono(
    fontSize: sizeBodyMedium,
    fontWeight: FontWeight.w500,
    color: HtbColors.textMono,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static TextStyle monoSmall = _mono(
    fontSize: sizeLabelMedium,
    fontWeight: FontWeight.w400,
    color: HtbColors.textSecondary,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static TextStyle monoLabel = _mono(
    fontSize: sizeLabelSmall,
    fontWeight: FontWeight.w500,
    color: HtbColors.textSecondary,
    letterSpacing: 0.35,
    height: 1.5,
  );

  static TextStyle monoNeon = _mono(
    fontSize: sizeBodySmall,
    fontWeight: FontWeight.w600,
    color: HtbColors.accentPrimary,
    letterSpacing: 0.5,
    height: 1.4,
  );

  static TextStyle monoFallback({
    double fontSize = sizeBodySmall,
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
