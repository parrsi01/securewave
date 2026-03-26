import 'package:flutter/material.dart';

/// SecureWave color system — deep slate, teal, and cool blue.
class AppColors {
  AppColors._();

  // ── Brand Primary (Teal) ────────────────────────────────────────────────

  static const Color primary = Color(0xFF1F7E78);
  static const Color primaryDark = Color(0xFF145D58);
  static const Color primaryDeep = Color(0xFF103D43);
  static const Color primaryBright = Color(0xFF4DDFC9);
  static const Color primaryLight = Color(0xFFD8F7F2);

  /// Translucent teal overlay
  static const Color primaryGhost = Color(0x144DDFC9);

  // ── Secondary (Cyan) ─────────────────────────────────────────────────

  static const Color secondary = Color(0xFF7BB8FF);
  static const Color secondaryDark = Color(0xFF4E80D1);
  static const Color secondaryLight = Color(0xFFDCE9FF);

  // ── Semantic / Status ─────────────────────────────────────────────────

  static const Color success = Color(0xFF4DDFC9);
  static const Color successDark = Color(0xFF2EAFA0);
  static const Color warning = Color(0xFFFFAB00);
  static const Color warningDark = Color(0xFFC26B1F);
  static const Color error = Color(0xFFFF7272);
  static const Color errorDark = Color(0xFFB3261E);

  static const Color successLight = Color(0xFFD8F7F2);
  static const Color warningLight = Color(0xFFF9E5D0);
  static const Color errorLight = Color(0xFFF5D6D4);

  // ── Light Mode Surfaces ────────────────────────────────────────────────

  static const Color background = Color(0xFFF7FBFC);
  static const Color backgroundWarm = Color(0xFFEEF5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F5F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Light Mode Text ────────────────────────────────────────────────────

  static const Color ink = Color(0xFF0C202A);
  static const Color inkMuted = Color(0xFF4E6470);
  static const Color inkSoft = Color(0xFF8095A0);

  // ── Light Mode Borders ─────────────────────────────────────────────────

  static const Color border = Color(0xFFDCE5EA);
  static const Color borderFocus = primary;

  // ── Dark Mode Surfaces (deep navy) ──────────────────────────────────

  static const Color darkBackground = Color(0xFF06131B);
  static const Color darkBackgroundWarm = Color(0xFF0A1A24);
  static const Color darkSurface = Color(0xFF102633);
  static const Color darkSurfaceMuted = Color(0xFF153243);
  static const Color darkSurfaceElevated = Color(0xFF163547);

  // ── Dark Mode Text ─────────────────────────────────────────────────────

  static const Color darkInk = Color(0xFFEAF6F7);
  static const Color darkInkMuted = Color(0xFFA0B8BF);
  static const Color darkInkSoft = Color(0xFF68818A);

  // ── Dark Mode Borders ──────────────────────────────────────────────────

  static const Color darkBorder = Color(0xFF173040);
  static const Color darkBorderFocus = primaryBright;

  // ── Glassmorphism Tokens ──────────────────────────────────────────────

  /// Frosted glass fill — light mode
  static Color get glassFillLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.72);

  /// Frosted glass fill — dark mode
  static Color get glassFillDark =>
      const Color(0xFF121E32).withValues(alpha: 0.80);

  /// Glass border — light mode
  static Color get glassBorderLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.4);

  /// Glass border — dark mode
  static Color get glassBorderDark =>
      const Color(0xFF4DDFC9).withValues(alpha: 0.12);

  // ── Gradient Presets ──────────────────────────────────────────────────

  /// Hero radial gradient (light mode) — centered on the connection ring
  static const Gradient heroGradientLight = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFFE4F8F7), Color(0xFFF7FBFC)],
    stops: [0.0, 1.0],
  );

  /// Hero radial gradient (dark mode)
  static const Gradient heroGradientDark = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFF112B34), Color(0xFF06131B)],
    stops: [0.0, 1.0],
  );

  /// Deep navy gradient — primary CTA (connect button, avatar, badges)
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, secondaryDark],
  );

  /// Auth screen header gradient (dark login page)
  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondaryDark],
  );

  /// Connected state gradient — sea-glass teal to cool blue
  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, secondary],
  );

  /// Navy depth gradient for shells / backgrounds
  static const Gradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkBackgroundWarm, darkBackground],
  );

  /// Cyan accent gradient
  static const Gradient cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, secondaryDark],
  );

  // ── ColorScheme Builders ──────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primaryDeep,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryDeep,
      secondary: secondary,
      onSecondary: ink,
      secondaryContainer: secondaryLight,
      onSecondaryContainer: const Color(0xFF113053),
      error: errorDark,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: inkMuted,
      outline: border,
      outlineVariant: const Color(0xFFEDF0F3),
      shadow: ink,
      scrim: ink,
    );
  }

  static ColorScheme darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryBright,
      onPrimary: darkBackground,
      primaryContainer: darkSurfaceElevated,
      onPrimaryContainer: primaryLight,
      secondary: secondary,
      onSecondary: darkBackground,
      surface: darkSurface,
      onSurface: darkInk,
      surfaceContainerLowest: darkBackground,
      surfaceContainerLow: darkBackgroundWarm,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkSurfaceMuted,
      surfaceContainerHighest: darkSurfaceElevated,
      onSurfaceVariant: darkInkMuted,
      outline: darkBorder,
      outlineVariant: const Color(0xFF143041),
      error: error,
      onError: darkBackground,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: darkInk,
      onInverseSurface: darkBackground,
      inversePrimary: primaryDeep,
    );
  }
}
